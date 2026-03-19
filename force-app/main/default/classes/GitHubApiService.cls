/**
 * @description     Service class for GitHub REST API integration.
 *                  Handles branch creation, file content updates, and Pull Request creation.
 *                  Uses Named Credential 'GitHub_API' for authentication.
 * 
 * @author          OneHub Platform Team
 * @date            2026-03-10
 * @group           GitHub Integration
 * 
 * ARCHITECTURE NOTES:
 * ─────────────────────────────────────────────────────────────────────
 * This service is designed to support AI-driven code remediation as part
 * of the Explainable Authentication Insight & Incident Intelligence POC.
 * 
 * When Agentforce identifies a code-level root cause from correlated
 * authentication logs, this service pushes the recommended fix to GitHub
 * as a Pull Request on a dedicated branch — never directly to main.
 * 
 * GitHub API Flow:
 *   1. GET  /repos/{owner}/{repo}/git/ref/heads/{base}    → Get base branch SHA
 *   2. POST /repos/{owner}/{repo}/git/refs                → Create fix branch
 *   3. GET  /repos/{owner}/{repo}/contents/{path}          → Get current file SHA
 *   4. PUT  /repos/{owner}/{repo}/contents/{path}          → Commit updated file
 *   5. POST /repos/{owner}/{repo}/pulls                    → Create Pull Request
 * 
 * All operations are auditable and traceable back to the originating
 * RFLIB Log Correlation ID.
 * ─────────────────────────────────────────────────────────────────────
 */
public with sharing class GitHubApiService {

    // ─── Constants ────────────────────────────────────────────────────
    private static final String NAMED_CREDENTIAL    = 'callout:GitHub_API';
    private static final String API_VERSION_HEADER  = '2022-11-28';
    private static final String ACCEPT_HEADER       = 'application/vnd.github+json';
    private static final String BRANCH_PREFIX       = 'ai-fix/';

    // ─── Configuration (from Custom Metadata) ─────────────────────────
    private String repoOwner;
    private String repoName;
    private String baseBranch;

    // ─── Inner Classes ────────────────────────────────────────────────

    /**
     * @description Wrapper for the result of a GitHub code fix operation.
     */
    public class CodeFixResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String branchName;
        @AuraEnabled public String pullRequestUrl;
        @AuraEnabled public String commitSha;
        @AuraEnabled public String errorMessage;

        public CodeFixResult() {
            this.success = false;
        }
    }

    /**
     * @description Wrapper for GitHub file content request payload.
     */
    public class GitHubFilePayload {
        public String message;
        public String content;  // Base64 encoded
        public String sha;      // Required for updates (existing file SHA)
        public String branch;

        public GitHubFilePayload(String message, String content, String sha, String branch) {
            this.message = message;
            this.content = content;
            this.sha = sha;
            this.branch = branch;
        }
    }

    /**
     * @description Wrapper for Pull Request creation payload.
     */
    public class PullRequestPayload {
        public String title;
        public String body;
        public String head;     // Source branch
        @SuppressWarnings('PMD.FieldNamingConventions')
        public String base_branch; // Target branch — serialised as "base" in toJson()

        public PullRequestPayload(String title, String body, String head, String baseBranch) {
            this.title = title;
            this.body = body;
            this.head = head;
            this.base_branch = baseBranch;
        }

        /**
         * @description Custom serialisation to handle the 'base' reserved-word conflict.
         */
        public String toJson() {
            Map<String, Object> payload = new Map<String, Object>{
                'title' => this.title,
                'body'  => this.body,
                'head'  => this.head,
                'base'  => this.base_branch
            };
            return JSON.serialize(payload);
        }
    }

    // ─── Constructor ──────────────────────────────────────────────────

    /**
     * @description Initialises the service using GitHub_Config__mdt custom metadata.
     */
    public GitHubApiService() {
        GitHub_Config__mdt config = GitHub_Config__mdt.getInstance('Default');
        if (config == null) {
            throw new GitHubApiException(
                'GitHub configuration metadata "Default" not found. ' +
                'Please create a GitHub_Config__mdt record with DeveloperName = Default.'
            );
        }
        this.repoOwner  = config.Repository_Owner__c;
        this.repoName   = config.Repository_Name__c;
        this.baseBranch  = config.Base_Branch__c;
    }

    /**
     * @description Overloaded constructor for explicit configuration (useful for testing).
     */
    public GitHubApiService(String repoOwner, String repoName, String baseBranch) {
        this.repoOwner  = repoOwner;
        this.repoName   = repoName;
        this.baseBranch  = baseBranch;
    }

    // ─── Public Methods ───────────────────────────────────────────────

    /**
     * @description Orchestrates the full code fix flow:
     *              Creates branch → Commits fix → Opens Pull Request.
     * 
     * @param filePath          Path to the file in the repository (e.g. force-app/main/default/classes/MyClass.cls)
     * @param updatedContent    The full updated file content (plain text, will be Base64-encoded)
     * @param commitMessage     Commit message describing the fix
     * @param correlationId     RFLIB Log Correlation ID for traceability
     * @param incidentSummary   Human-readable summary of the incident for the PR body
     * @return CodeFixResult    Result wrapper with branch name, PR URL, and status
     */
    public CodeFixResult pushCodeFix(
        String filePath,
        String updatedContent,
        String commitMessage,
        String correlationId,
        String incidentSummary
    ) {
        CodeFixResult result = new CodeFixResult();

        try {
            // Step 1: Get the base branch HEAD SHA
            String baseSha = getBaseBranchSha();

            // Step 2: Create the fix branch
            String branchName = BRANCH_PREFIX + correlationId;
            createBranch(branchName, baseSha);
            result.branchName = branchName;

            // Step 3: Get the current file SHA (required for update)
            String fileSha = getFileSha(filePath, this.baseBranch);

            // Step 4: Commit the updated file to the fix branch
            String encodedContent = EncodingUtil.base64Encode(
                Blob.valueOf(updatedContent)
            );

            String fullCommitMessage = commitMessage + 
                '\n\nCorrelation-ID: ' + correlationId +
                '\nGenerated-By: OneHub AI Incident Intelligence';

            GitHubFilePayload filePayload = new GitHubFilePayload(
                fullCommitMessage,
                encodedContent,
                fileSha,
                branchName
            );

            String commitSha = commitFile(filePath, filePayload);
            result.commitSha = commitSha;

            // Step 5: Create Pull Request
            String prTitle = '[AI Fix] ' + commitMessage;
            String prBody  = buildPullRequestBody(correlationId, incidentSummary, filePath);

            String prUrl = createPullRequest(
                new PullRequestPayload(prTitle, prBody, branchName, this.baseBranch)
            );
            result.pullRequestUrl = prUrl;

            result.success = true;

        } catch (GitHubApiException e) {
            result.errorMessage = e.getMessage();
            System.debug(LoggingLevel.ERROR, 'GitHubApiService.pushCodeFix failed: ' + e.getMessage());
        } catch (Exception e) {
            result.errorMessage = 'Unexpected error: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'GitHubApiService.pushCodeFix unexpected error: ' + e.getMessage() + 
                             ' | Stack: ' + e.getStackTraceString());
        }

        return result;
    }

    // ─── Private Methods: GitHub API Calls ─────────────────────────────

    /**
     * @description Retrieves the SHA of the HEAD commit on the base branch.
     */
    private String getBaseBranchSha() {
        String endpoint = buildRepoUrl('/git/ref/heads/' + this.baseBranch);
        HttpResponse response = executeGet(endpoint);

        Map<String, Object> body = parseResponse(response, 200);
        Map<String, Object> obj = (Map<String, Object>) body.get('object');
        return (String) obj.get('sha');
    }

    /**
     * @description Creates a new branch from the given SHA.
     */
    private void createBranch(String branchName, String sha) {
        String endpoint = buildRepoUrl('/git/refs');

        Map<String, Object> payload = new Map<String, Object>{
            'ref' => 'refs/heads/' + branchName,
            'sha' => sha
        };

        HttpResponse response = executePost(endpoint, JSON.serialize(payload));
        parseResponse(response, 201);
    }

    /**
     * @description Retrieves the current SHA of a file (required for updates).
     *              Returns null if the file does not exist (new file scenario).
     */
    private String getFileSha(String filePath, String branch) {
        String endpoint = buildRepoUrl('/contents/' + filePath + '?ref=' + branch);

        try {
            HttpResponse response = executeGet(endpoint);
            if (response.getStatusCode() == 404) {
                return null; // File doesn't exist yet — will be created
            }
            Map<String, Object> body = parseResponse(response, 200);
            return (String) body.get('sha');
        } catch (GitHubApiException e) {
            // File not found — treat as new file
            if (e.getMessage().contains('404')) {
                return null;
            }
            throw e;
        }
    }

    /**
     * @description Commits a file to the repository (create or update).
     * @return The commit SHA
     */
    private String commitFile(String filePath, GitHubFilePayload payload) {
        String endpoint = buildRepoUrl('/contents/' + filePath);

        Map<String, Object> payloadMap = new Map<String, Object>{
            'message' => payload.message,
            'content' => payload.content,
            'branch'  => payload.branch
        };

        // Only include SHA if updating an existing file
        if (String.isNotBlank(payload.sha)) {
            payloadMap.put('sha', payload.sha);
        }

        HttpResponse response = executePut(endpoint, JSON.serialize(payloadMap));
        Map<String, Object> body = parseResponse(response, new Set<Integer>{ 200, 201 });
        Map<String, Object> commitObj = (Map<String, Object>) body.get('commit');
        return (String) commitObj.get('sha');
    }

    /**
     * @description Creates a Pull Request in the repository.
     * @return The HTML URL of the created Pull Request
     */
    private String createPullRequest(PullRequestPayload payload) {
        String endpoint = buildRepoUrl('/pulls');

        HttpResponse response = executePost(endpoint, payload.toJson());
        Map<String, Object> body = parseResponse(response, 201);
        return (String) body.get('html_url');
    }

    // ─── Private Methods: HTTP Execution ──────────────────────────────

    private HttpResponse executeGet(String endpoint) {
        return execute('GET', endpoint, null);
    }

    private HttpResponse executePost(String endpoint, String body) {
        return execute('POST', endpoint, body);
    }

    private HttpResponse executePut(String endpoint, String body) {
        return execute('PUT', endpoint, body);
    }

    /**
     * @description Executes an HTTP request against the GitHub API using Named Credentials.
     */
    private HttpResponse execute(String method, String endpoint, String body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(method);
        req.setHeader('Accept', ACCEPT_HEADER);
        req.setHeader('X-GitHub-Api-Version', API_VERSION_HEADER);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(30000); // 30 second timeout

        if (String.isNotBlank(body)) {
            req.setBody(body);
        }

        Http http = new Http();
        HttpResponse response = http.send(req);

        System.debug(LoggingLevel.INFO, 
            'GitHub API ' + method + ' ' + endpoint + 
            ' → ' + response.getStatusCode()
        );

        return response;
    }

    // ─── Private Methods: Utilities ───────────────────────────────────

    /**
     * @description Builds the full repository API URL.
     */
    private String buildRepoUrl(String path) {
        return NAMED_CREDENTIAL + '/repos/' + this.repoOwner + '/' + this.repoName + path;
    }

    /**
     * @description Parses the HTTP response and validates the status code.
     */
    private Map<String, Object> parseResponse(HttpResponse response, Integer expectedStatus) {
        return parseResponse(response, new Set<Integer>{ expectedStatus });
    }

    /**
     * @description Parses the HTTP response and validates against a set of acceptable status codes.
     */
    private Map<String, Object> parseResponse(HttpResponse response, Set<Integer> acceptableStatuses) {
        if (!acceptableStatuses.contains(response.getStatusCode())) {
            String errorDetail = '';
            try {
                Map<String, Object> errorBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                errorDetail = (String) errorBody.get('message');
            } catch (Exception e) {
                errorDetail = response.getBody();
            }
            throw new GitHubApiException(
                'GitHub API returned ' + response.getStatusCode() + ': ' + errorDetail
            );
        }
        return (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
    }

    /**
     * @description Constructs a formatted Pull Request body with full traceability.
     */
    private String buildPullRequestBody(String correlationId, String incidentSummary, String filePath) {
        return '## AI-Generated Code Fix\n\n' +
               '**Correlation ID:** `' + correlationId + '`\n' +
               '**File Modified:** `' + filePath + '`\n' +
               '**Generated By:** OneHub AI Incident Intelligence (Agentforce)\n\n' +
               '---\n\n' +
               '### Incident Summary\n\n' +
               incidentSummary + '\n\n' +
               '---\n\n' +
               '### Review Checklist\n\n' +
               '- [ ] Code change addresses the identified root cause\n' +
               '- [ ] No unintended side effects introduced\n' +
               '- [ ] Unit tests pass in scratch org validation\n' +
               '- [ ] Reviewed by platform team member\n' +
               '- [ ] Approved for deployment to target environment\n\n' +
               '---\n\n' +
               '> **⚠️ Governance Note:** This fix was generated by AI and must be reviewed ' +
               'and approved by a human before merge. Do not auto-merge AI-generated PRs.\n\n' +
               '_Traced from RFLIB Log Correlation ID: ' + correlationId + '_';
    }

    // ─── Custom Exception ─────────────────────────────────────────────

    public class GitHubApiException extends Exception {}
}