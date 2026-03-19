/**
 * @description     Controller for the deployCodeFix Lightning Web Component.
 *                  Provides @AuraEnabled methods to:
 *                    1. Retrieve the recommended fix details from the Parent Log record
 *                    2. Trigger the GitHub code fix push via GitHubApiService
 * 
 * @author          OneHub Platform Team
 * @date            2026-03-10
 * @group           GitHub Integration
 * 
 * USAGE:
 * ─────────────────────────────────────────────────────────────────────
 * This controller is invoked by the deployCodeFix LWC, which is placed
 * on the Parent Log record page as a Quick Action or embedded component.
 * 
 * The Parent Log record must have:
 *   - Recommended_Fix__c          (Long Text Area) — the updated code
 *   - Fix_File_Path__c            (Text)           — repo file path
 *   - Fix_Commit_Message__c       (Text)           — commit summary
 *   - Correlation_Id__c           (Text)           — RFLIB correlation ID
 *   - Incident_Summary__c          (Long Text Area) — Agentforce explanation
 *   - Fix_Deployed_To_GitHub__c   (Checkbox)       — deployment status flag
 *   - GitHub_PR_URL__c            (URL)            — PR link after deployment
 * ─────────────────────────────────────────────────────────────────────
 */
public with sharing class GitHubCodeFixController {

    /**
     * @description Wrapper class for returning fix details to the LWC.
     */
    public class FixDetails {
        @AuraEnabled public String recommendedFix;
        @AuraEnabled public String filePath;
        @AuraEnabled public String commitMessage;
        @AuraEnabled public String correlationId;
        @AuraEnabled public String incidentSummary;
        @AuraEnabled public Boolean alreadyDeployed;
        @AuraEnabled public String existingPrUrl;
    }

    /**
     * @description Retrieves the recommended fix details from the Parent Log record.
     * @param recordId The ID of the Parent Log record
     * @return FixDetails wrapper with all fields needed for the GitHub push
     */
    @AuraEnabled(cacheable=true)
    public static FixDetails getFixDetails(Id recordId) {
        try {
            rflib_Log__c logRecord = [
                SELECT 
                    Recommended_Fix__c,
                    Fix_File_Path__c,
                    Fix_Commit_Message__c,
                    Correlation_Id__c,
                    Incident_Summary__c,
                    Fix_Deployed_To_GitHub__c,
                    GitHub_PR_URL__c
                FROM rflib_Log__c
                WHERE Id = :recordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            FixDetails details = new FixDetails();
            details.recommendedFix   = logRecord.Recommended_Fix__c;
            details.filePath         = logRecord.Fix_File_Path__c;
            details.commitMessage    = logRecord.Fix_Commit_Message__c;
            details.correlationId    = logRecord.Correlation_Id__c;
            details.incidentSummary  = logRecord.Incident_Summary__c;
            details.alreadyDeployed  = logRecord.Fix_Deployed_To_GitHub__c;
            details.existingPrUrl    = logRecord.GitHub_PR_URL__c;

            return details;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'GitHubCodeFixController.getFixDetails error: ' + e.getMessage());
            throw new AuraHandledException(
                'Unable to retrieve fix details: ' + e.getMessage()
            );
        }
    }

    /**
     * @description Pushes the recommended code fix to GitHub as a new branch and Pull Request.
     *              Updates the Parent Log record with the PR URL and deployment status.
     * 
     * @param recordId The ID of the Parent Log record
     * @return GitHubApiService.CodeFixResult with the PR URL, branch name, and status
     */
    @AuraEnabled
    public static GitHubApiService.CodeFixResult deployFixToGitHub(Id recordId) {
        try {
            // 1. Retrieve the fix details
            rflib_Log__c logRecord = [
                SELECT 
                    Recommended_Fix__c,
                    Fix_File_Path__c,
                    Fix_Commit_Message__c,
                    Correlation_Id__c,
                    Incident_Summary__c,
                    Fix_Deployed_To_GitHub__c
                FROM rflib_Log__c
                WHERE Id = :recordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            // 2. Validate — prevent duplicate deployments
            if (logRecord.Fix_Deployed_To_GitHub__c) {
                GitHubApiService.CodeFixResult result = new GitHubApiService.CodeFixResult();
                result.success = false;
                result.errorMessage = 'This fix has already been deployed to GitHub. ' +
                                     'Check the existing Pull Request.';
                return result;
            }

            // 3. Validate — ensure all required fields are populated
            validateFixFields(logRecord);

            // 4. Execute the GitHub push
            GitHubApiService service = new GitHubApiService();
            GitHubApiService.CodeFixResult result = service.pushCodeFix(
                logRecord.Fix_File_Path__c,
                logRecord.Recommended_Fix__c,
                logRecord.Fix_Commit_Message__c,
                logRecord.Correlation_Id__c,
                logRecord.Incident_Summary__c
            );

            // 5. Update the Parent Log record with the result
            if (result.success) {
                logRecord.Fix_Deployed_To_GitHub__c = true;
                logRecord.GitHub_PR_URL__c          = result.pullRequestUrl;
                logRecord.GitHub_Branch_Name__c     = result.branchName;
                logRecord.GitHub_Commit_SHA__c      = result.commitSha;
                logRecord.Fix_Deployed_Date__c      = Datetime.now();

                update logRecord;
            }

            return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 
                'GitHubCodeFixController.deployFixToGitHub error: ' + e.getMessage() +
                ' | Stack: ' + e.getStackTraceString()
            );
            throw new AuraHandledException(
                'Failed to deploy fix to GitHub: ' + e.getMessage()
            );
        }
    }

    /**
     * @description Validates that all required fields for a GitHub push are populated.
     */
    private static void validateFixFields(rflib_Log__c logRecord) {
        List<String> missingFields = new List<String>();

        if (String.isBlank(logRecord.Recommended_Fix__c)) {
            missingFields.add('Recommended Fix');
        }
        if (String.isBlank(logRecord.Fix_File_Path__c)) {
            missingFields.add('Fix File Path');
        }
        if (String.isBlank(logRecord.Fix_Commit_Message__c)) {
            missingFields.add('Fix Commit Message');
        }
        if (String.isBlank(logRecord.Correlation_Id__c)) {
            missingFields.add('Correlation ID');
        }

        if (!missingFields.isEmpty()) {
            throw new AuraHandledException(
                'Cannot deploy fix — the following fields are required: ' +
                String.join(missingFields, ', ')
            );
        }
    }
}