/**
 * CorrelatedLogInsights
 * ---------------------
 * Retrieves all child RFLIB_Log__c records related to a parent RFLIB_Log__c
 * via the self-lookup Parent__c field, and returns a structured JSON payload
 * suitable for Agentforce Prompt Builder.
 *
 * Usage:
 *   - Wire this class into your Prompt Template via the Invocable Action picker.
 *   - The input is the parent RFLIB_Log__c record (the correlation anchor).
 *   - The output is a JSON string containing all child log messages,
 *     ordered chronologically, ready for AI consumption.
 */
public with sharing class CorrelatedLogInsights {

    @InvocableMethod(label='Get Correlated RFLIB Log Messages for AI Analysis')
    public static List<Response> getCorrelatedLogs(List<Request> requests) {
        List<Response> responses = new List<Response>();

        try {
            Set<Id> parentLogIds = new Set<Id>();
            for (Request req : requests) {
                if (req.parentLog != null && req.parentLog.Id != null) {
                    parentLogIds.add(req.parentLog.Id);
                }
            }

            if (parentLogIds.isEmpty()) {
                System.debug('CorrelatedLogInsights: No Parent Log Ids provided.');
                return responses;
            }

            // Query all child RFLIB_Log__c records via the self-lookup
            Map<Id, List<RFLIB_Log__c>> parentToChildLogs = new Map<Id, List<RFLIB_Log__c>>();
            for (RFLIB_Log__c log : [
                SELECT Id,
                       Parent__c,
                       Created_Date_Sim__c,
                       Platform_Context__c,
                       Platform_Request_Id__c,
                       Platform_Log_Messages__c
                FROM RFLIB_Log__c
                WHERE Parent__c IN :parentLogIds
                ORDER BY Created_Date_Sim__c ASC
            ]) {
                if (!parentToChildLogs.containsKey(log.Parent__c)) {
                    parentToChildLogs.put(log.Parent__c, new List<RFLIB_Log__c>());
                }
                parentToChildLogs.get(log.Parent__c).add(log);
            }

            // Build structured JSON response per parent log
            for (Id parentId : parentLogIds) {
                List<RFLIB_Log__c> childLogs = parentToChildLogs.containsKey(parentId)
                    ? parentToChildLogs.get(parentId)
                    : new List<RFLIB_Log__c>();

                Map<String, Object> payload = new Map<String, Object>();
                payload.put('ParentLogId', parentId);
                payload.put('TotalLogRecords', childLogs.size());

                List<Map<String, Object>> logEntries = new List<Map<String, Object>>();
                for (RFLIB_Log__c log : childLogs) {
                    Map<String, Object> entry = new Map<String, Object>();
                    entry.put('Timestamp', log.Created_Date_Sim__c);
                    entry.put('Component', log.Platform_Context__c);
                    entry.put('LogMessages', log.Platform_Log_Messages__c);
                    logEntries.add(entry);
                }
                payload.put('LogRecords', logEntries);

                Response resp = new Response();
                resp.prompt = JSON.serializePretty(payload);
                responses.add(resp);
            }

        } catch (Exception exc) {
            System.debug('CorrelatedLogInsights Exception: ' + exc.getMessage());
            System.debug('Stack Trace: ' + exc.getStackTraceString());
        }

        return responses;
    }

    // Request Wrapper
    public class Request {
        @InvocableVariable(label='Parent Log Record' required=true)
        public RFLIB_Log__c parentLog;
    }

    // Response Wrapper
    public class Response {
        @InvocableVariable(label='Prompt')
        public String prompt;
    }
}