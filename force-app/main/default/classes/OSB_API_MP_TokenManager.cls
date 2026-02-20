public with sharing class OSB_API_MP_TokenManager {
    
    // Cached token stored in a static variable for the transaction
    private static String cachedAccessToken;
    private static DateTime cachedTokenExpiry;
    
    public static String getValidToken() {
/*
        // This method is the primary entry point for any class that needs an
        // authenticated token to call the IBM API Connect (API Marketplace) endpoints.
        //
        // It implements a simple caching strategy:
        // 1. Check if a cached token exists and is still valid
        // 2. If valid, return the cached token (avoids unnecessary callouts)
        // 3. If expired or not found, call refreshToken() to get a new one
        //
        // CALLERS:
        // - OSB_OD_ProductCatalogue_CTRL.authenticateWithAPIProducts() at line 48
        //   (which is called by getIBMAppSubscriptions at line 253 and getClientRequests at line 71)
        //
        // The IBM API Marketplace requires a valid OAuth token for all API calls.
        // This token is obtained by authenticating against the API Marketplace
        // using credentials stored in a Custom Setting: BCW_CIB_OH_APIMarketPlace_E__c
        
        RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('OSB_API_MP_TokenManager');
        
        try {
            // ====================================================================
            // CHECK 1: Is there a cached token that is still valid?
            // ====================================================================
            // On the first call in a transaction, cachedAccessToken is null.
            // On subsequent calls (e.g. getIBMAppSubscriptions then getClientRequests),
            // the token is already cached and can be reused.
            //
            // This is the "Using cached token" INFO log entry seen in some log records.
            
            if (cachedAccessToken != null && cachedTokenExpiry != null && 
                cachedTokenExpiry > System.now()) {
                
                logger.info('Using cached token');
                return cachedAccessToken;
            }
            
            // ====================================================================
            // CHECK 2: Token needs refresh or not found
            // ====================================================================
            // If we reach here, either:
            //   a) No cached token exists (first call in the transaction)
            //   b) The cached token has expired
            //
            // This generates the INFO log entry:
            // "Token needs refresh or not found, requesting new token"
            
            logger.info('Token needs refresh or not found, requesting new token');
            
            // ====================================================================
            // LINE 115: CALLS refreshToken() — WHERE THE ERROR PROPAGATES FROM
            // ====================================================================
            //
            // WHAT HAPPENS:
            // 1. getValidToken() calls refreshToken() at line 115
            // 2. refreshToken() attempts to read credentials from Custom Setting
            // 3. The Custom Setting field 'username' does not exist (see refreshToken)
            // 4. Salesforce throws: "Field BCW_CIB_OH_APIMarketPlace_E.username 
            //    does not exist. Check spelling."
            // 5. Exception propagates back to this method
            //
            // STACK TRACE SHOWS:
            // "Class.OSB_API_MP_TokenManager.refreshToken: line 152, column 1"
            // "Class.OSB_API_MP_TokenManager.getValidToken: line 115, column 1"
            // "Class.OSB_OD_ProductCatalogue_CTRL.authenticateWithAPIProducts: line 48, column 1"
            // (and then either getIBMAppSubscriptions: line 253 or getClientRequests: line 71)
            
            String newToken = refreshToken(); // LINE 115: CALLS refreshToken()
            
            if (String.isNotBlank(newToken)) {
                cachedAccessToken = newToken;
                cachedTokenExpiry = System.now().addMinutes(55); // Token valid for ~1 hour
                logger.info('Token refreshed and cached successfully');
                return cachedAccessToken;
            } else {
                logger.error('Failed to refresh token');
                return null;
            }
            
        } catch (Exception e) {
            // ====================================================================
            // EXCEPTION HANDLING — Token refresh failure
            // ====================================================================
            //
            // When refreshToken() fails, this catch block:
            // 1. Logs the error via RFLIB
            // 2. Logs "Failed to refresh token" as a separate entry
            // 3. Returns null — the caller must handle the null token
            //
            // The RFLIB log entries created here match what we see in the 
            // correlated authentication journey logs:
            //
            // "Exception during token refresh: Message: Field BCW_CIB_OH_APIMarketPlace_E.username 
            //  does not exist. Check spelling."
            // "Failed to refresh token"
            
            logger.error('Exception during token refresh: ' +
                '\nMessage: ' + e.getMessage() +
                '\nStracktrace: ' + e.getStackTraceString());
            
            logger.error('Failed to refresh token');
            
            return null;
        }
*/
        return null;
    }
    
    private static String refreshToken() {
/*
        // This method performs the actual OAuth token exchange with the IBM API
        // Marketplace (API Connect) to obtain an access token.
        //
        // It reads credentials from a Salesforce Custom Setting and makes an
        // HTTP callout to the API Marketplace token endpoint.
        //
        // ====================================================================
        // THE ROOT CAUSE OF THE ERROR IS IN THIS METHOD
        // ====================================================================
        //
        // The Custom Setting is: BCW_CIB_OH_APIMarketPlace_E__c
        // (a hierarchical or list Custom Setting storing API credentials)
        //
        // PROBLEM:
        // The code references a field called 'username' on the Custom Setting,
        // but the actual field API name is 'Username__c' (with the __c suffix).
        //
        // This is a common issue that occurs when:
        //   a) A Custom Setting field is renamed or recreated
        //   b) The code was written against a different org's schema
        //   c) A deployment omitted the Custom Setting field definition
        //   d) The field was deleted during a metadata cleanup
        //
        // The result is a runtime exception because Salesforce cannot resolve
        // the field reference at execution time.
        
        RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('OSB_API_MP_TokenManager');
        
        try {
            logger.info('Initiating token refresh with API Marketplace');
            
            // ====================================================================
            // RETRIEVE CREDENTIALS FROM CUSTOM SETTING
            // ====================================================================
            //
            // BCW_CIB_OH_APIMarketPlace_E__c is a Custom Setting that stores:
            //   - Token endpoint URL
            //   - Client ID
            //   - Client Secret
            //   - Username (for Resource Owner Password Grant)
            //   - Password
            //
            // The Custom Setting is expected to have an org-default record.
            
            BCW_CIB_OH_APIMarketPlace_E__c apiConfig = BCW_CIB_OH_APIMarketPlace_E__c.getOrgDefaults();
            
            // Validate that the configuration exists
            if (apiConfig == null || apiConfig.Id == null) {
                logger.error('API Marketplace configuration not found in Custom Setting');
                throw new CustomException('API Marketplace configuration is missing');
            }
            
            // ====================================================================
            // LINE 152: THE PROBLEM — Field does not exist
            // ====================================================================
            //
            // WHAT HAPPENS:
            // 1. The code attempts to access apiConfig.username
            // 2. The field 'username' does not exist on BCW_CIB_OH_APIMarketPlace_E__c
            // 3. The correct field API name is 'Username__c'
            // 4. Salesforce throws: "Field BCW_CIB_OH_APIMarketPlace_E.username 
            //    does not exist. Check spelling."
            //
            // IMPORTANT DETAIL:
            // This is NOT a compile-time error because the field reference is
            // accessed dynamically through the SObject.get() method or through
            // a dynamic reference pattern. In Apex, if you use:
            //   String username = (String) apiConfig.get('username');
            // It will compile but fail at runtime if the field doesn't exist.
            //
            // If the code used:
            //   String username = apiConfig.Username__c;
            // It would fail at compile time and never deploy.
            //
            // THE FIX:
            // Change 'username' to 'Username__c' in the dynamic field reference.
            // Or better: use the strongly-typed field reference apiConfig.Username__c
            
            String tokenEndpoint = (String) apiConfig.get('Token_Endpoint__c');
            String clientId = (String) apiConfig.get('Client_Id__c');
            String clientSecret = (String) apiConfig.get('Client_Secret__c');
            String username = (String) apiConfig.get('username'); // LINE 152: FAILS HERE — should be 'Username__c'
            String password = (String) apiConfig.get('Password__c');
            
            logger.info('Token endpoint: ' + tokenEndpoint);
            logger.debug('Client ID: ' + clientId);
            
            // ====================================================================
            // BUILD TOKEN REQUEST (never reached due to line 152 failure)
            // ====================================================================
            // The following code would execute the OAuth Resource Owner Password
            // Credentials grant to obtain an access token from IBM API Connect.
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(tokenEndpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(30000); // 30 second timeout
            
            String requestBody = 'grant_type=password' +
                '&client_id=' + EncodingUtil.urlEncode(clientId, 'UTF-8') +
                '&client_secret=' + EncodingUtil.urlEncode(clientSecret, 'UTF-8') +
                '&username=' + EncodingUtil.urlEncode(username, 'UTF-8') +
                '&password=' + EncodingUtil.urlEncode(password, 'UTF-8') +
                '&scope=read';
            
            req.setBody(requestBody);
            
            logger.info('Sending token request to API Marketplace');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> tokenResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                String accessToken = (String) tokenResponse.get('access_token');
                
                logger.info('Successfully obtained token from API Marketplace');
                return accessToken;
                
            } else {
                logger.error('API Marketplace token request failed with status: ' + res.getStatusCode());
                logger.error('Response body: ' + res.getBody());
                return null;
            }
            
        } catch (Exception e) {
            logger.error('Exception during token refresh: ' +
                '\nMessage: ' + e.getMessage() +
                '\nStracktrace: ' + e.getStackTraceString());
            
            throw e; // Re-throw to be caught by getValidToken()
        }
*/
        return null;
    }
    
    public class CustomException extends Exception {}
}
