public with sharing class OSB_OD_ProductCatalogue_CTRL {
    
    // IBM API Connect base endpoint for the API Marketplace
    private static final String IBM_API_BASE_URL = 'https://api-gateway.standardbank.co.za/sb/api-marketplace/v1';
    
    private static String authenticateWithAPIProducts() {
/*
        // This method obtains a valid authentication token from the API Marketplace
        // by delegating to OSB_API_MP_TokenManager.
        //
        // It acts as a wrapper that validates the token and provides meaningful
        // error messages when authentication fails.
        //
        // CALLERS:
        // - getIBMAppSubscriptions() at line 253
        // - getClientRequests() at line 71
        //
        // Both callers need a valid token before making API calls to IBM API Connect.
        
        RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('OSB_OD_ProductCatalogue_CTRL');
        
        try {
            logger.info('authenticateWithAPIProducts called');
            
            // ====================================================================
            // LINE 48: CALLS TokenManager.getValidToken() — ERROR PROPAGATION POINT
            // ====================================================================
            //
            // WHAT HAPPENS:
            // 1. authenticateWithAPIProducts() calls OSB_API_MP_TokenManager.getValidToken()
            // 2. getValidToken() calls refreshToken() at line 115
            // 3. refreshToken() tries to read 'username' field from Custom Setting at line 152
            // 4. Field doesn't exist → "Field BCW_CIB_OH_APIMarketPlace_E.username 
            //    does not exist. Check spelling."
            // 5. Exception propagates: refreshToken → getValidToken → this method
            // 6. getValidToken() catches the exception and returns null
            // 7. This method receives null and logs the failure
            //
            // STACK TRACE IN LOGS SHOWS:
            // "Class.OSB_API_MP_TokenManager.refreshToken: line 152, column 1"
            // "Class.OSB_API_MP_TokenManager.getValidToken: line 115, column 1"
            // "Class.OSB_OD_ProductCatalogue_CTRL.authenticateWithAPIProducts: line 48, column 1"
            //
            // Then depending on the caller:
            // "Class.OSB_OD_ProductCatalogue_CTRL.getIBMAppSubscriptions: line 253, column 1"
            // OR
            // "Class.OSB_OD_ProductCatalogue_CTRL.getClientRequests: line 71, column 1"
            
            String token = OSB_API_MP_TokenManager.getValidToken(); // LINE 48
            
            if (String.isBlank(token)) {
                // ====================================================================
                // TOKEN IS NULL — TokenManager failed to obtain a valid token
                // ====================================================================
                //
                // This generates the RFLIB log entry:
                // "OSB_OD_ProductCatalogue_CTRL : authenticateWithAPIProducts - 
                //  Failed to get valid token from TokenManager"
                //
                // The null token is the result of the Custom Setting field reference
                // error in OSB_API_MP_TokenManager.refreshToken(). The TokenManager
                // catches the exception internally and returns null rather than
                // propagating the exception.
                
                logger.error('OSB_OD_ProductCatalogue_CTRL : authenticateWithAPIProducts - ' +
                    'Failed to get valid token from TokenManager');
                
                return null;
            }
            
            logger.info('Successfully authenticated with API Products service');
            return token;
            
        } catch (Exception e) {
            logger.error('OSB_OD_ProductCatalogue_CTRL : authenticateWithAPIProducts - ' +
                'Exception: ' + e.getMessage());
            
            return null;
        }
*/
        return null;
    }
    
    public static Map<String, Object> getClientRequests() {
/*
        // This method retrieves the list of API subscription requests submitted by
        // the current client/customer from the IBM API Marketplace.
        //
        // It is called by the OneHub dashboard to display pending and approved
        // API access requests for the customer's organisation.
        //
        // The method:
        // 1. Authenticates with the API Marketplace (via TokenManager)
        // 2. Makes an HTTP GET request to the client requests endpoint
        // 3. Parses and returns the response
        
        RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('OSB_OD_ProductCatalogue_CTRL');
        
        try {
            logger.info('getClientRequests called');
            
            // ====================================================================
            // LINE 71: CALLS authenticateWithAPIProducts() — ERROR PROPAGATION POINT
            // ====================================================================
            //
            // WHAT HAPPENS:
            // 1. getClientRequests() calls authenticateWithAPIProducts() at line 71
            // 2. authenticateWithAPIProducts() calls TokenManager.getValidToken() at line 48
            // 3. TokenManager fails due to Custom Setting field reference error
            // 4. authenticateWithAPIProducts() returns null
            // 5. This method detects null token and logs the failure
            //
            // STACK TRACE IN LOGS SHOWS (full chain):
            // "Class.OSB_API_MP_TokenManager.refreshToken: line 152, column 1"
            // "Class.OSB_API_MP_TokenManager.getValidToken: line 115, column 1"
            // "Class.OSB_OD_ProductCatalogue_CTRL.authenticateWithAPIProducts: line 48, column 1"
            // "Class.OSB_OD_ProductCatalogue_CTRL.getClientRequests: line 71, column 1"
            
            String accessToken = authenticateWithAPIProducts(); // LINE 71
            
            if (String.isBlank(accessToken)) {
                // ====================================================================
                // AUTHENTICATION FAILED — Cannot proceed with API call
                // ====================================================================
                //
                // This generates the RFLIB log entry:
                // "OSB_OD_ProductCatalogue_CTRL : getClientRequests - 
                //  Failed to authenticate with API Products service"
                //
                // The entire API call chain fails because the TokenManager could
                // not obtain a valid token. The root cause is the missing Custom
                // Setting field, but from this method's perspective, the symptom
                // is simply "authentication failed".
                
                logger.error('OSB_OD_ProductCatalogue_CTRL : getClientRequests - ' +
                    'Failed to authenticate with API Products service');
                
                throw new AuraHandledException(
                    'Unable to retrieve your API requests. Authentication with the API service failed.'
                );
            }
            
            // ====================================================================
            // MAKE API CALL TO IBM API CONNECT (never reached due to auth failure)
            // ====================================================================
            // If authentication succeeded, this would call the client requests
            // endpoint on IBM API Connect to retrieve the customer's API
            // subscription requests.
            
            String clientRequestsEndpoint = IBM_API_BASE_URL + '/portal/me/requests';
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(clientRequestsEndpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Accept', 'application/json');
            req.setHeader('X-IBM-Client-Id', getClientId());
            req.setTimeout(30000);
            
            logger.info('Calling IBM API Connect: ' + clientRequestsEndpoint);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                logger.info('Successfully retrieved client requests');
                return response;
                
            } else {
                logger.error('OSB_OD_ProductCatalogue_CTRL : getClientRequests - ' +
                    'HTTP Error: ' + res.getStatusCode() + ' - ' + res.getBody());
                
                throw new AuraHandledException(
                    'Failed to retrieve API requests. HTTP Status: ' + res.getStatusCode()
                );
            }
            
        } catch (AuraHandledException ae) {
            throw ae;
            
        } catch (Exception e) {
            logger.error('OSB_OD_ProductCatalogue_CTRL : getClientRequests - ' +
                'Exception: ' + e.getMessage() +
                '\nStracktrace: ' + e.getStackTraceString());
            
            throw new AuraHandledException(
                'An unexpected error occurred while retrieving API requests.'
            );
        }
*/
        return null;
    }
    
    private static String getClientId() {
/*
        // Helper method to retrieve the IBM API Connect client ID
        // from the Custom Setting or Custom Metadata
        
        BCW_CIB_OH_APIMarketPlace_E__c apiConfig = BCW_CIB_OH_APIMarketPlace_E__c.getOrgDefaults();
        return (String) apiConfig.get('Client_Id__c');
*/
        return null;
    }
    
    public static Map<String, Object> getIBMAppSubscriptions() {
/*
        // This method retrieves the list of API application subscriptions for the
        // current user from the IBM API Marketplace (API Connect).
        //
        // It is called by the OneHub Experience Cloud LWC component when the user
        // navigates to the API product catalogue or application management page.
        //
        // The method:
        // 1. Authenticates with the API Marketplace (via TokenManager)
        // 2. Retrieves the user's IBM organisation ID
        // 3. Makes an HTTP GET request to the subscriptions endpoint
        // 4. Parses and returns the subscription data
        //
        // TWO DISTINCT ERROR PATTERNS ARE OBSERVED IN THE LOGS:
        //
        // PATTERN A (from correlated authentication journey - Custom Setting error):
        //   Root cause: Custom Setting field 'username' does not exist
        //   Flow: getIBMAppSubscriptions → authenticateWithAPIProducts → TokenManager → FAIL
        //   Log: "Failed to authenticate with API Products service"
        //
        // PATTERN B (from document 3 - Logs.xlsx additional entries):
        //   Root cause: Cached token is valid BUT the API user does not exist in IBM
        //   Flow: getIBMAppSubscriptions → authenticateWithAPIProducts → TokenManager (cached) → API call → HTTP 400
        //   Log: "HTTP Error: 400 - {"message":"API user not found","error":"Bad Request","statusCode":400}"
        //
        // PATTERN B occurs when:
        //   - The TokenManager has a valid cached token (no refresh needed)
        //   - The API call succeeds in authenticating
        //   - But the IBM API Connect user record doesn't exist or is deactivated
        //   - IBM returns HTTP 400 with "API user not found"
        
        RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('OSB_OD_ProductCatalogue_CTRL');
        
        try {
            logger.info('getIBMAppSubscriptions called');
            
            // Get the current user context
            String currentUserId = UserInfo.getUserId();
            
            // Retrieve the user's contact and organisation details
            // This is needed to map the Salesforce user to an IBM API Connect organisation
            User currentUser = [
                SELECT Id, Name, Email, ContactId, Contact.AccountId,
                       Contact.Account.Name, Contact.Account.IBM_Org_Id__c
                FROM User
                WHERE Id = :currentUserId
                LIMIT 1
            ];
            
            logger.info('User: ' + currentUser.Name);
            logger.info('Organisation: ' + currentUser.Contact.Account.Name);
            
            // ====================================================================
            // LINE 253: CALLS authenticateWithAPIProducts() — ERROR PROPAGATION POINT
            // ====================================================================
            //
            // PATTERN A FAILURE (Custom Setting field error):
            // 1. getIBMAppSubscriptions() calls authenticateWithAPIProducts() at line 253
            // 2. authenticateWithAPIProducts() calls TokenManager.getValidToken() at line 48
            // 3. TokenManager.getValidToken() calls refreshToken() at line 115
            // 4. refreshToken() fails at line 152: field 'username' does not exist
            // 5. Token is null → authenticateWithAPIProducts() returns null
            // 6. This method detects null and logs failure
            //
            // FULL STACK TRACE FOR PATTERN A:
            // "Class.OSB_API_MP_TokenManager.refreshToken: line 152, column 1"
            // "Class.OSB_API_MP_TokenManager.getValidToken: line 115, column 1"
            // "Class.OSB_OD_ProductCatalogue_CTRL.authenticateWithAPIProducts: line 48, column 1"
            // "Class.OSB_OD_ProductCatalogue_CTRL.getIBMAppSubscriptions: line 253, column 1"
            
            String accessToken = authenticateWithAPIProducts(); // LINE 253
            
            if (String.isBlank(accessToken)) {
                logger.error('OSB_OD_ProductCatalogue_CTRL : getIBMAppSubscriptions - ' +
                    'Failed to authenticate with API Products service');
                
                throw new AuraHandledException(
                    'Unable to retrieve your API subscriptions. Authentication failed.'
                );
            }
            
            // ====================================================================
            // MAKE API CALL TO IBM API CONNECT — SUBSCRIPTIONS ENDPOINT
            // ====================================================================
            //
            // This is where PATTERN B occurs:
            // - Authentication succeeded (token was cached and valid)
            // - But the IBM API Connect user does not exist
            // - IBM returns HTTP 400: "API user not found"
            //
            // This happens when:
            //   a) The user's IBM API Connect account was never provisioned
            //   b) The user's IBM account was deactivated or deleted
            //   c) The organisation mapping (IBM_Org_Id__c) is incorrect
            //   d) There is a mismatch between the Salesforce user and IBM user
            
            String ibmOrgId = currentUser.Contact.Account.IBM_Org_Id__c;
            String subscriptionsEndpoint = IBM_API_BASE_URL + 
                '/portal/orgs/' + ibmOrgId + '/subscriptions';
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(subscriptionsEndpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Accept', 'application/json');
            req.setHeader('X-IBM-Client-Id', getClientId());
            req.setTimeout(30000);
            
            logger.info('Calling IBM API Connect: ' + subscriptionsEndpoint);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> subscriptions = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                
                logger.info('Successfully retrieved IBM app subscriptions');
                logger.info('Number of subscriptions: ' + 
                    ((List<Object>) subscriptions.get('results')).size());
                
                return subscriptions;
                
            } else if (res.getStatusCode() == 400) {
                // ====================================================================
                // PATTERN B: HTTP 400 — API user not found
                // ====================================================================
                //
                // This generates the RFLIB log entry seen in the Logs.xlsx data:
                //
                // "OSB_OD_ProductCatalogue_CTRL : getIBMAppSubscriptions - HTTP Error: 400 - 
                //  {"message":"API user not found","error":"Bad Request","statusCode":400}"
                //
                // The INFO log preceding this shows:
                // "Using cached token" (from TokenManager — token was valid)
                //
                // ROOT CAUSE:
                // The Salesforce user is authenticated and has a valid API token,
                // but the corresponding user account in IBM API Connect does not
                // exist. This is a provisioning gap — the user was created in
                // Salesforce/Ping but not provisioned in IBM API Connect.
                //
                // IMPACT:
                // The user cannot view their API subscriptions or manage API access.
                // The OneHub dashboard shows an error state for the API catalogue section.
                
                logger.error('OSB_OD_ProductCatalogue_CTRL : getIBMAppSubscriptions - ' +
                    'HTTP Error: ' + res.getStatusCode() + ' - ' + res.getBody());
                
                throw new AuraHandledException(
                    'Your API marketplace account could not be found. Please contact support to ' +
                    'verify your API access has been provisioned.'
                );
                
            } else if (res.getStatusCode() == 401) {
                logger.error('OSB_OD_ProductCatalogue_CTRL : getIBMAppSubscriptions - ' +
                    'Unauthorized: Token may have expired during request');
                
                throw new AuraHandledException(
                    'Session expired. Please refresh the page and try again.'
                );
                
            } else {
                logger.error('OSB_OD_ProductCatalogue_CTRL : getIBMAppSubscriptions - ' +
                    'HTTP Error: ' + res.getStatusCode() + ' - ' + res.getBody());
                
                throw new AuraHandledException(
                    'Failed to retrieve API subscriptions. Please try again later.'
                );
            }
            
        } catch (AuraHandledException ae) {
            throw ae;
            
        } catch (Exception e) {
            logger.error('OSB_OD_ProductCatalogue_CTRL : getIBMAppSubscriptions - ' +
                'Exception: ' + e.getMessage() +
                '\nStracktrace: ' + e.getStackTraceString());
            
            throw new AuraHandledException(
                'An unexpected error occurred while retrieving API subscriptions.'
            );
        }
*/
        return null;
    }
}