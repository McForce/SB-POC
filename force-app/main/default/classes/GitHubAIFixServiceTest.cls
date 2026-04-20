/**
 * GitHubAIFixServiceTest
 *
 * Unit tests for GitHubAIFixService covering positive, negative, and error paths.
 * All HTTP callouts are mocked — no live network calls.
 */
@IsTest
private class GitHubAIFixServiceTest {

    // ─── Mock HTTP callout ────────────────────────────────────────────────────

    private class GitHubMock implements HttpCalloutMock {
        private final Integer statusCode;
        private final String  body;

        GitHubMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body       = body;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body ?? '');
            return res;
        }
    }

    // ─── Test data factory ────────────────────────────────────────────────────

    private static RFLIB_Log__c createLogRecord(String rootCause) {
        RFLIB_Log__c log = new RFLIB_Log__c(
            Platform_Log_Level__c                        = 'ERROR',
            Platform_Context__c                          = 'Mall_Ping_AuthProviderCustomPlugin.handleCallback',
            Apex_Code_Root_Cause_Determination_Promp__c  = rootCause,
            AI_Fix_Status__c                             = 'Send for Fix'
        );
        insert log;
        return log;
    }

    // ─── Tests ────────────────────────────────────────────────────────────────

    @IsTest
    static void testSuccess_204_updatesStatusToProcessing() {
        RFLIB_Log__c log = createLogRecord('Class: Mall_Ping_AuthProviderCustomPlugin\nMethod: handleCallback\nLine: 47\nError: NullPointerException\nFix: Add null check before accessing authResponse.');

        Test.setMock(HttpCalloutMock.class, new GitHubMock(204, ''));

        GitHubAIFixService.Request req = new GitHubAIFixService.Request();
        req.recordId = log.Id;

        Test.startTest();
        List<GitHubAIFixService.Response> responses = GitHubAIFixService.triggerFix(
            new List<GitHubAIFixService.Request>{ req }
        );
        Test.stopTest();

        Assert.areEqual(1, responses.size(), 'Expected exactly one response');
        Assert.isTrue(responses[0].success, 'Expected success = true for 204 response');
        Assert.isTrue(
            responses[0].message.containsIgnoreCase('Processing'),
            'Expected message to mention Processing'
        );

        RFLIB_Log__c updated = [SELECT AI_Fix_Status__c FROM RFLIB_Log__c WHERE Id = :log.Id];
        Assert.areEqual('Processing', updated.AI_Fix_Status__c, 'Status should be updated to Processing');
    }

    @IsTest
    static void testFailure_missingRootCause_returnsError() {
        RFLIB_Log__c log = createLogRecord(null);

        GitHubAIFixService.Request req = new GitHubAIFixService.Request();
        req.recordId = log.Id;

        Test.startTest();
        List<GitHubAIFixService.Response> responses = GitHubAIFixService.triggerFix(
            new List<GitHubAIFixService.Request>{ req }
        );
        Test.stopTest();

        Assert.areEqual(1, responses.size());
        Assert.isFalse(responses[0].success, 'Expected success = false when root cause is empty');
        Assert.isTrue(
            responses[0].message.containsIgnoreCase('Root Cause'),
            'Expected message to reference Root Cause'
        );
    }

    @IsTest
    static void testFailure_github404_repositoryNotFound() {
        RFLIB_Log__c log = createLogRecord('Class: SomeClass\nFix: Add null check.');

        Test.setMock(HttpCalloutMock.class, new GitHubMock(404, '{"message":"Not Found"}'));

        GitHubAIFixService.Request req = new GitHubAIFixService.Request();
        req.recordId = log.Id;

        Test.startTest();
        List<GitHubAIFixService.Response> responses = GitHubAIFixService.triggerFix(
            new List<GitHubAIFixService.Request>{ req }
        );
        Test.stopTest();

        Assert.isFalse(responses[0].success, 'Expected failure for 404');
        Assert.isTrue(
            responses[0].message.contains('404'),
            'Expected 404 mentioned in message'
        );
    }

    @IsTest
    static void testFailure_github401_authenticationFailed() {
        RFLIB_Log__c log = createLogRecord('Class: SomeClass\nFix: Add null check.');

        Test.setMock(HttpCalloutMock.class, new GitHubMock(401, '{"message":"Bad credentials"}'));

        GitHubAIFixService.Request req = new GitHubAIFixService.Request();
        req.recordId = log.Id;

        Test.startTest();
        List<GitHubAIFixService.Response> responses = GitHubAIFixService.triggerFix(
            new List<GitHubAIFixService.Request>{ req }
        );
        Test.stopTest();

        Assert.isFalse(responses[0].success, 'Expected failure for 401');
        Assert.isTrue(
            responses[0].message.contains('401'),
            'Expected 401 mentioned in message'
        );
    }

    @IsTest
    static void testFailure_githubUnexpectedStatus_returnsGenericError() {
        RFLIB_Log__c log = createLogRecord('Class: SomeClass\nFix: Add null check.');

        Test.setMock(HttpCalloutMock.class, new GitHubMock(500, '{"message":"Internal Server Error"}'));

        GitHubAIFixService.Request req = new GitHubAIFixService.Request();
        req.recordId = log.Id;

        Test.startTest();
        List<GitHubAIFixService.Response> responses = GitHubAIFixService.triggerFix(
            new List<GitHubAIFixService.Request>{ req }
        );
        Test.stopTest();

        Assert.isFalse(responses[0].success, 'Expected failure for 500');
        Assert.isTrue(
            responses[0].message.contains('500'),
            'Expected status code 500 mentioned in message'
        );
    }

    @IsTest
    static void testFailure_recordNotFound_returnsError() {
        // Use a syntactically valid but non-existent Id
        Id fakeId = '001000000000001AAA';

        GitHubAIFixService.Request req = new GitHubAIFixService.Request();
        req.recordId = fakeId;

        Test.startTest();
        List<GitHubAIFixService.Response> responses = GitHubAIFixService.triggerFix(
            new List<GitHubAIFixService.Request>{ req }
        );
        Test.stopTest();

        Assert.isFalse(responses[0].success, 'Expected failure for non-existent record');
        Assert.isTrue(
            responses[0].message.containsIgnoreCase('not found'),
            'Expected "not found" in error message'
        );
    }

    @IsTest
    static void testBulk_multipleRequests_allProcessed() {
        List<RFLIB_Log__c> logs = new List<RFLIB_Log__c>();
        for (Integer i = 0; i < 5; i++) {
            logs.add(new RFLIB_Log__c(
                Platform_Log_Level__c                       = 'ERROR',
                Platform_Context__c                         = 'BulkContext.' + i,
                Apex_Code_Root_Cause_Determination_Promp__c = 'Class: BulkClass' + i + '\nFix: fix ' + i,
                AI_Fix_Status__c                            = 'Send for Fix'
            ));
        }
        insert logs;

        Test.setMock(HttpCalloutMock.class, new GitHubMock(204, ''));

        List<GitHubAIFixService.Request> requests = new List<GitHubAIFixService.Request>();
        for (RFLIB_Log__c log : logs) {
            GitHubAIFixService.Request req = new GitHubAIFixService.Request();
            req.recordId = log.Id;
            requests.add(req);
        }

        Test.startTest();
        List<GitHubAIFixService.Response> responses = GitHubAIFixService.triggerFix(requests);
        Test.stopTest();

        Assert.areEqual(5, responses.size(), 'Expected 5 responses for 5 requests');
        for (GitHubAIFixService.Response res : responses) {
            Assert.isTrue(res.success, 'All bulk requests should succeed');
        }
    }
}
