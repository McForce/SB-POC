/**
 * GitHubAIFixService
 *
 * Invocable Apex service that dispatches a GitHub Actions workflow when an
 * RFLIB_Log__c record is flagged for automated fixing.
 *
 * Flow → @InvocableMethod → GitHub repository_dispatch → AI Fix workflow
 *
 * Logging strategy: all log entries are buffered in a static list and flushed
 * via a single insert at the very end of triggerFix(), after all callouts are
 * complete. This avoids the "uncommitted work pending" governor limit error
 * that occurs when DML precedes a callout in the same transaction.
 */
public with sharing class GitHubAIFixService {

    private static final String GITHUB_API_BASE   = 'https://api.github.com';
    private static final String DISPATCH_PATH     = '/repos/{0}/{1}/dispatches';
    private static final String EVENT_TYPE        = 'ai-fix-request';
    private static final String STATUS_PROCESSING = 'Processing';
    private static final String LOG_CONTEXT       = 'GitHubAIFixService';

    // Buffered log entries — flushed after all callouts are complete
    private static List<RFLIB_Log__c> pendingLogs = new List<RFLIB_Log__c>();

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
        pendingLogs.clear();

        // All callouts must complete before any DML to avoid the
        // "uncommitted work pending" governor limit restriction.
        List<Response> responses   = new List<Response>();
        List<Id>       idsToUpdate = new List<Id>();

        for (Request req : requests) {
            Response res = processRequest(req);
            responses.add(res);
            if (res.success) {
                idsToUpdate.add(req.recordId);
            }
        }

        // Batch DML after all callouts — status update first, then log flush
        try {
            if (!idsToUpdate.isEmpty()) {
                batchUpdateLogStatus(idsToUpdate, STATUS_PROCESSING);
            }
        } finally {
            flushLogs();
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
            addLog('ERROR', 'processRequest', 'GitHub_AI_Fix_Config__mdt "Production" not found. '
                + 'Deploy the custom metadata record before using this service. '
                + 'Log record Id: ' + req.recordId);
            return res;
        }
        if (!config.Enabled__c) {
            res.success = false;
            res.message = 'GitHub AI Fix integration is currently disabled via configuration.';
            addLog('WARN', 'processRequest', 'Integration disabled (Enabled__c = false) on the "Production" '
                + 'config record. Enable it in Setup → Custom Metadata to resume processing. '
                + 'Log record Id: ' + req.recordId);
            return res;
        }

        // 2. Query the log record
        RFLIB_Log__c logRecord = queryLogRecord(req.recordId);
        if (logRecord == null) {
            res.success = false;
            res.message = 'RFLIB_Log__c record not found for Id: ' + req.recordId;
            addLog('ERROR', 'processRequest', 'No RFLIB_Log__c record found for Id: ' + req.recordId
                + '. The record may have been deleted or the Id is invalid.');
            return res;
        }

        // 3. Validate root cause is populated
        if (String.isBlank(logRecord.Apex_Code_Root_Cause_Determination_Promp__c)) {
            res.success = false;
            res.message = 'Apex Code Root Cause Determination is empty. Populate this field before sending for fix.';
            addLog('WARN', 'processRequest', 'Apex_Code_Root_Cause_Determination_Promp__c is blank on log record '
                + logRecord.Id + ' ("' + logRecord.Name + '"). Dispatch skipped.');
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
        } else if (statusCode == 401) {
            res.success = false;
            res.message = 'GitHub authentication failed (401). Check the GitHub Token in configuration.';
            addLog('FATAL', 'handleResponse', 'GitHub authentication failed (401) for log record ' + logRecordId
                + '. The GitHub Token in GitHub_AI_Fix_Config__mdt is invalid or has expired — rotate it immediately.');
        } else if (statusCode == 404) {
            res.success = false;
            res.message = 'GitHub repository not found (404). Check Repository Owner and Repository Name in configuration.';
            addLog('ERROR', 'handleResponse', 'GitHub returned 404 for log record ' + logRecordId
                + '. Verify Repository_Owner__c and Repository_Name__c in GitHub_AI_Fix_Config__mdt.');
        } else if (statusCode == 422) {
            res.success = false;
            res.message = 'GitHub API rejected the request (422). Verify the workflow file and event_type are correctly configured.';
            addLog('ERROR', 'handleResponse', 'GitHub returned 422 Unprocessable Entity for log record ' + logRecordId
                + '. Confirm the workflow file exists and the event_type "' + EVENT_TYPE + '" matches the workflow trigger. '
                + 'Response body: ' + httpRes.getBody());
        } else {
            res.success = false;
            res.message = 'GitHub API returned unexpected status ' + statusCode + ': ' + httpRes.getBody();
            addLog('ERROR', 'handleResponse', 'Unexpected HTTP ' + statusCode + ' from GitHub API for log record '
                + logRecordId + '. Response body: ' + httpRes.getBody());
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
        try {
            update as system logsToUpdate;
        } catch (DmlException e) {
            addLog('FATAL', 'batchUpdateLogStatus', 'DML failure updating AI_Fix_Status__c to "' + status
                + '" for ' + logsToUpdate.size() + ' record(s). Error: ' + e.getMessage());
            throw e;
        }
    }

    // ─── Log buffer ──────────────────────────────────────────────────────────

    private static void addLog(String level, String method, String message) {
        pendingLogs.add(new RFLIB_Log__c(
            Name                    = (LOG_CONTEXT + ': ' + level).left(80),
            Platform_Log_Level__c   = level,
            Platform_Context__c     = LOG_CONTEXT + '.' + method + '()',
            Platform_Log_Messages__c = message
        ));
    }

    private static void flushLogs() {
        if (pendingLogs.isEmpty()) {
            return;
        }
        try {
            insert as system pendingLogs;
        } catch (DmlException e) {
            // Swallow — logging must never break the primary service flow
            System.debug(LoggingLevel.ERROR,
                'GitHubAIFixService.flushLogs() — failed to insert diagnostic log records: ' + e.getMessage());
        } finally {
            pendingLogs.clear();
        }
    }
}
