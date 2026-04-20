/**
 * GitHubAIFixService
 *
 * Invocable Apex service that dispatches a GitHub Actions workflow when an
 * RFLIB_Log__c record is flagged for automated fixing.
 *
 * Flow → @InvocableMethod → GitHub repository_dispatch → AI Fix workflow
 */
public with sharing class GitHubAIFixService {

    private static final String GITHUB_API_BASE  = 'https://api.github.com';
    private static final String DISPATCH_PATH    = '/repos/{0}/{1}/dispatches';
    private static final String EVENT_TYPE       = 'ai-fix-request';
    private static final String STATUS_PROCESSING = 'Processing';

    // ─── Invocable input / output ────────────────────────────────────────────

    public class Request {
        @InvocableVariable(label='Log Record Id' required=true)
        public Id recordId;
    }

    public class Response {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Message')
        public String message;
    }

    // ─── Entry point ─────────────────────────────────────────────────────────

    @InvocableMethod(
        label='Trigger GitHub AI Fix'
        description='Dispatches a GitHub Actions workflow to generate an AI-powered fix for the supplied RFLIB_Log__c record.'
        category='AI Fix'
    )
    public static List<Response> triggerFix(List<Request> requests) {
        // All callouts must complete before any DML to avoid the
        // "uncommitted work pending" governor limit restriction.
        List<Response>      responses       = new List<Response>();
        List<Id>            idsToUpdate     = new List<Id>();

        for (Request req : requests) {
            Response res = processRequest(req);
            responses.add(res);
            if (res.success) {
                idsToUpdate.add(req.recordId);
            }
        }

        // Batch DML after all callouts
        if (!idsToUpdate.isEmpty()) {
            batchUpdateLogStatus(idsToUpdate, STATUS_PROCESSING);
        }

        return responses;
    }

    // ─── Core logic ──────────────────────────────────────────────────────────

    @TestVisible
    private static Response processRequest(Request req) {
        Response res = new Response();

        // 1. Load and validate configuration
        GitHub_AI_Fix_Config__mdt config = loadConfig();
        if (config == null) {
            res.success = false;
            res.message = 'GitHub AI Fix Config metadata record "Production" not found.';
            return res;
        }
        if (!config.Enabled__c) {
            res.success = false;
            res.message = 'GitHub AI Fix integration is currently disabled via configuration.';
            return res;
        }

        // 2. Query the log record
        RFLIB_Log__c logRecord = queryLogRecord(req.recordId);
        if (logRecord == null) {
            res.success = false;
            res.message = 'RFLIB_Log__c record not found for Id: ' + req.recordId;
            return res;
        }

        // 3. Validate root cause is populated
        if (String.isBlank(logRecord.Apex_Code_Root_Cause_Determination_Promp__c)) {
            res.success = false;
            res.message = 'Apex Code Root Cause Determination is empty. Populate this field before sending for fix.';
            return res;
        }

        // 4. Build and send the GitHub dispatch payload
        String endpoint = String.format(
            GITHUB_API_BASE + DISPATCH_PATH,
            new List<String>{ config.Repository_Owner__c, config.Repository_Name__c }
        );

        String payload = buildPayload(logRecord);
        HttpResponse httpRes = sendDispatch(endpoint, config.GitHub_Token__c, payload);

        // 5. Handle response
        return handleResponse(httpRes, logRecord.Id, res);
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    @TestVisible
    private static GitHub_AI_Fix_Config__mdt loadConfig() {
        List<GitHub_AI_Fix_Config__mdt> configs = [
            SELECT GitHub_Token__c, Repository_Owner__c, Repository_Name__c, Enabled__c
            FROM   GitHub_AI_Fix_Config__mdt
            WHERE  DeveloperName = 'Production'
            LIMIT  1
        ];
        return configs.isEmpty() ? null : configs[0];
    }

    @TestVisible
    private static RFLIB_Log__c queryLogRecord(Id recordId) {
        List<RFLIB_Log__c> records = [
            SELECT Id,
                   Name,
                   CreatedDate,
                   Platform_Log_Level__c,
                   Platform_Context__c,
                   Apex_Code_Root_Cause_Determination_Promp__c,
                   AI_Fix_Status__c
            FROM   RFLIB_Log__c
            WHERE  Id = :recordId
            LIMIT  1
        ];
        return records.isEmpty() ? null : records[0];
    }

    @TestVisible
    private static String buildPayload(RFLIB_Log__c logRecord) {
        Map<String, Object> clientPayload = new Map<String, Object>{
            'incidentId'             => (String) logRecord.Id,
            'incidentName'           => logRecord.Name,
            'timestamp'              => logRecord.CreatedDate?.format('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''),
            'logLevel'               => logRecord.Platform_Log_Level__c,
            'context'                => logRecord.Platform_Context__c,
            'rootCauseDetermination' => logRecord.Apex_Code_Root_Cause_Determination_Promp__c
        };

        Map<String, Object> body = new Map<String, Object>{
            'event_type'     => EVENT_TYPE,
            'client_payload' => clientPayload
        };

        return JSON.serialize(body);
    }

    @TestVisible
    private static HttpResponse sendDispatch(String endpoint, String token, String payload) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization',        'Bearer ' + token);
        req.setHeader('Accept',               'application/vnd.github+json');
        req.setHeader('Content-Type',         'application/json');
        req.setHeader('X-GitHub-Api-Version', '2022-11-28');
        req.setBody(payload);

        return new Http().send(req);
    }

    @TestVisible
    private static Response handleResponse(HttpResponse httpRes, Id logRecordId, Response res) {
        Integer statusCode = httpRes.getStatusCode();

        if (statusCode == 204) {
            res.success = true;
            res.message = 'GitHub Actions workflow dispatched successfully. Status updated to Processing.';
        } else if (statusCode == 404) {
            res.success = false;
            res.message = 'GitHub repository not found (404). Check Repository Owner and Repository Name in configuration.';
        } else if (statusCode == 401) {
            res.success = false;
            res.message = 'GitHub authentication failed (401). Check the GitHub Token in configuration.';
        } else {
            res.success = false;
            res.message = 'GitHub API returned unexpected status ' + statusCode + ': ' + httpRes.getBody();
        }

        return res;
    }

    @TestVisible
    private static void batchUpdateLogStatus(List<Id> recordIds, String status) {
        List<RFLIB_Log__c> logsToUpdate = new List<RFLIB_Log__c>();
        for (Id recordId : recordIds) {
            logsToUpdate.add(new RFLIB_Log__c(
                Id               = recordId,
                AI_Fix_Status__c = status
            ));
        }
        update as system logsToUpdate;
    }
}
