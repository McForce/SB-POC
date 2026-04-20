global class Mall_Ping_AuthProviderCustomPlugin implements Auth.AuthProviderPlugin {
    
    global String getCustomMetadataType() {
/*
        // Return the custom metadata type that stores this provider's configuration
        // This is used by Salesforce to retrieve the provider settings
        return 'Mall_Ping_Provider__mdt';
*/
        return null;
    }
    
    global System.PageReference initiate(Map<String, String> authProviderConfiguration, String stateToPropagate) {
/*
        // This method is called when user clicks "Sign in with Ping"
        // It redirects the user to the Ping identity provider
        // stateToPropagate is used to maintain state between the redirect and callback
        
        String clientId = authProviderConfiguration.get('Client_Id__c');
        String redirectUri = authProviderConfiguration.get('Redirect_URI__c');
        String pingAuthorizationEndpoint = authProviderConfiguration.get('Authorization_Endpoint__c');
        
        RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('Mall_Ping_AuthProviderCustomPlugin');
        logger.info('Initiating authentication flow with Ping');
        logger.debug('Client ID: ' + clientId);
        logger.debug('Redirect URI: ' + redirectUri);
        
        // Build authorization URL
        String authorizationUrl = pingAuthorizationEndpoint + 
            '?client_id=' + clientId +
            '&redirect_uri=' + EncodingUtil.urlEncode(redirectUri, 'UTF-8') +
            '&response_type=code' +
            '&state=' + EncodingUtil.urlEncode(stateToPropagate, 'UTF-8') +
            '&scope=openid%20profile%20email';
        
        logger.info('Redirecting to Ping authorization endpoint');
        
        // Redirect user to Ping
        return new System.PageReference(authorizationUrl);
*/
        return null;
    }
    
    global Auth.AuthProviderTokenResponse handleCallback(Map<String, String> authProviderConfiguration, 
                                                         Auth.AuthProviderCallbackState state) {
/*
        // Configuration constants (hardcoded - no timeout value!)
        // THIS IS THE PROBLEM: No timeout configuration or timeout too high
        String BCB_PLATFORM_ENDPOINT = 'https://bcb-platform.standardbank.co.za/oauth/token';
        String PING_VALIDATION_ENDPOINT = 'https://ping.standardbank.co.za/api/validate';
        
        // Timeout is missing or set too high - default HTTP timeout is 120 seconds
        // Salesforce will wait full 120 seconds before throwing "Read timed out"
        // Integer HTTP_TIMEOUT_MS = 120000; // TOO HIGH!
        
        // NO TIMEOUT CONFIGURED - This is the root cause!
        
        try {
            // Extract authorization code from OAuth callback
            String authorizationCode = state.queryParameters.get('code');
            String state_param = state.queryParameters.get('state');
            
            RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('Mall_Ping_AuthProviderCustomPlugin');
            
            // Log authentication attempt
            logger.info('OAuth callback received from Ping');
            logger.info('Authorization Code: ' + authorizationCode.substring(0, 10) + '...');
            
            // Prepare request to exchange authorization code for access token
            // This request is sent to BCB Platform (external service)
            
            String clientId = authProviderConfiguration.get('Client_Id__c');
            String clientSecret = authProviderConfiguration.get('Client_Secret__c');
            
            // Build token exchange request
            String tokenRequestBody = 'grant_type=authorization_code' +
                                     '&code=' + authorizationCode +
                                     '&client_id=' + clientId +
                                     '&client_secret=' + clientSecret +
                                     '&redirect_uri=' + authProviderConfiguration.get('Redirect_URI__c');
            
            // Create HTTP request object
            HttpRequest req = new HttpRequest();
            req.setEndpoint(BCB_PLATFORM_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setHeader('Accept', 'application/json');
            req.setBody(tokenRequestBody);
            
            // ====================================================================
            // LINE 246: THE PROBLEM - HTTP.send() with no timeout configuration
            // ====================================================================
            // This is where the error occurs: "Read timed out"
            // 
            // WHAT HAPPENS:
            // 1. HTTP.send() is called
            // 2. Request goes to BCB Platform at bcb-platform.standardbank.co.za
            // 3. BCB Platform is slow or temporarily unavailable
            // 4. Request waits for response (default Salesforce timeout = 120 seconds)
            // 5. After 120 seconds with no response, HTTP.send() throws exception
            // 6. Exception message: "Read timed out"
            // 7. Stack trace shows: "line 246"
            //
            // WHY NO TIMEOUT SET:
            // The code does NOT call req.setTimeout(milliseconds)
            // So Salesforce uses default timeout of 120 seconds
            // 120 seconds is too long - BCB Platform doesn't respond
            //
            // BETTER APPROACH:
            // 1. Set explicit timeout: req.setTimeout(10000); // 10 seconds
            // 2. Wrap in try-catch for timeout exceptions
            // 3. Implement retry logic with exponential backoff
            // 4. Check BCB Platform health before calling
            // 5. Implement circuit breaker pattern
            
            logger.info('Initiating token exchange with BCB Platform');
            logger.info('Calling endpoint: ' + BCB_PLATFORM_ENDPOINT);
            logger.debug('Request body: ' + tokenRequestBody);
            
            // ====================================================================
            // THIS LINE WILL TIMEOUT - NO TIMEOUT CONFIGURATION
            // ====================================================================
            Http http = new Http();
            HttpResponse res = http.send(req);  // LINE 246: This will timeout!
            // ====================================================================
            
            // If we get here, BCB Platform responded
            logger.info('BCB Platform responded with status: ' + res.getStatusCode());
            
            // Parse response
            if (res.getStatusCode() == 200) {
                // Process successful token response
                Map<String, Object> tokenResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                String accessToken = (String) tokenResponse.get('access_token');
                String idToken = (String) tokenResponse.get('id_token');
                String tokenType = (String) tokenResponse.get('token_type');
                
                logger.info('Successfully obtained access token from BCB Platform');
                logger.debug('Token type: ' + tokenType);
                
                // Create and return OAuth response
                Auth.AuthProviderTokenResponse response = new Auth.AuthProviderTokenResponse(
                    'Ping',           // provider name
                    accessToken,      // access token
                    'refresh_token',  // refresh token (if available)
                    System.now().addSeconds(3600)  // expiration time
                );
                
                return response;
                
            } else if (res.getStatusCode() == 401) {
                logger.error('Unauthorized: Invalid client credentials for BCB Platform');
                MallExceptionUtil.logAuthException('401 - Unauthorized', 'Invalid credentials');
                throw new Auth.AuthProviderPluginException('Authentication failed: Invalid credentials');
                
            } else if (res.getStatusCode() == 403) {
                logger.error('Forbidden: Access denied by BCB Platform');
                MallExceptionUtil.logAuthException('403 - Forbidden', 'Access denied');
                throw new Auth.AuthProviderPluginException('Authentication failed: Access denied');
                
            } else {
                logger.error('BCB Platform returned error: ' + res.getStatusCode());
                MallExceptionUtil.logAuthException('HTTP_ERROR_' + res.getStatusCode(), res.getBody());
                throw new Auth.AuthProviderPluginException('Token exchange failed with status: ' + res.getStatusCode());
            }
            
        } catch (System.CalloutException e) {
            // THIS IS WHERE THE TIMEOUT EXCEPTION IS CAUGHT
            // Exception type: System.CalloutException
            // Exception message: "Read timed out"
            // This occurs when HTTP.send() takes longer than allowed
            
            RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('Mall_Ping_AuthProviderCustomPlugin');
            
            String errorMessage = e.getMessage();  // "Read timed out"
            String exceptionType = e.getTypeName();  // "System.CalloutException"
            
            logger.error('Callout exception during OAuth callback: ' + errorMessage);
            logger.error('Exception type: ' + exceptionType);
            logger.error('Stack trace: ' + e.getStackTraceString());
            
            // Log the exception for analysis
            MallExceptionUtil.logAuthException(exceptionType, errorMessage);
            MallExceptionUtil.logStackTrace(e.getStackTraceString());
            
            // Check if this is a timeout
            if (errorMessage.contains('timed out') || errorMessage.contains('Timeout')) {
                logger.error('BCB Platform timeout: Service did not respond within acceptable time');
                
                // Generate RFLIB logs that match the error scenario
                // This creates the logs we see in the error data:
                // "Read timed out"
                // "Class.Mall_Ping_AuthProviderCustomPlugin.handleCallback: line 246, column 1"
                
                throw new Auth.AuthProviderPluginException(
                    'Authentication service timeout: BCB Platform did not respond. Please try again.'
                );
            }
            
            throw new Auth.AuthProviderPluginException('Authentication failed: ' + errorMessage);
            
        } catch (Exception e) {
            // Catch any other unexpected exceptions
            RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('Mall_Ping_AuthProviderCustomPlugin');
            logger.error('Unexpected exception in handleCallback: ' + e.getMessage());
            logger.error('Stack trace: ' + e.getStackTraceString());
            
            MallExceptionUtil.logAuthException(e.getTypeName(), e.getMessage());
            MallExceptionUtil.logStackTrace(e.getStackTraceString());
            
            throw new Auth.AuthProviderPluginException('Authentication failed: ' + e.getMessage());
        }
*/
        return null;
    }
    
    global Auth.UserData getUserInfo(Map<String, String> authProviderConfiguration, Auth.AuthProviderTokenResponse response) {
        // This method extracts user information from the authorization provider's userinfo endpoint
        // and returns it as Auth.UserData object that Salesforce uses for user account provisioning
        
        // FIX: Added null safety check for response to prevent NullPointerException
        // Root cause: response or response.oauthToken could be null, causing userAttributes to be null
        if (response == null || response.oauthToken == null) {
            RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('Mall_Ping_AuthProviderCustomPlugin');
            logger.error('getUserInfo called with null response or token');
            throw new Auth.AuthProviderPluginException('Cannot retrieve user info: Invalid authentication response');
        }
        
        try {
            String userInfoEndpoint = authProviderConfiguration.get('User_Info_Endpoint__c');
            
            // FIX: Added null safety check for configuration
            if (String.isBlank(userInfoEndpoint)) {
                throw new Auth.AuthProviderPluginException('User Info Endpoint not configured');
            }
            
            RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('Mall_Ping_AuthProviderCustomPlugin');
            logger.info('Retrieving user info from endpoint: ' + userInfoEndpoint);
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(userInfoEndpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + response.oauthToken);
            req.setHeader('Accept', 'application/json');
            req.setTimeout(10000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> userAttributes = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                
                // FIX: Added null safety check for userAttributes to prevent NullPointerException
                // This is the core fix for the root cause: userAttributes could be null if JSON parsing fails
                if (userAttributes == null) {
                    logger.error('Failed to parse user info response: userAttributes is null');
                    throw new Auth.AuthProviderPluginException('Invalid user info response format');
                }
                
                logger.info('Successfully retrieved user info');
                
                // FIX: Added defensive coding with safe string extraction using ternary operators
                // This prevents NullPointerException when userAttributes contains null values
                String userId = userAttributes.containsKey('sub') ? String.valueOf(userAttributes.get('sub')) : null;
                String firstName = userAttributes.containsKey('given_name') ? String.valueOf(userAttributes.get('given_name')) : '';
                String lastName = userAttributes.containsKey('family_name') ? String.valueOf(userAttributes.get('family_name')) : '';
                String fullName = userAttributes.containsKey('name') ? String.valueOf(userAttributes.get('name')) : (firstName + ' ' + lastName).trim();
                String email = userAttributes.containsKey('email') ? String.valueOf(userAttributes.get('email')) : null;
                String username = email;
                
                // FIX: Added validation for required fields
                if (String.isBlank(userId) || String.isBlank(email)) {
                    logger.error('Missing required user attributes: userId or email is blank');
                    throw new Auth.AuthProviderPluginException('User info missing required fields');
                }
                
                return new Auth.UserData(
                    userId,        // identifier
                    firstName,     // firstName
                    lastName,      // lastName
                    fullName,      // fullName
                    email,         // email
                    null,          // link
                    username,      // username
                    null,          // locale
                    'Ping',        // provider
                    null,          // siteLoginUrl
                    userAttributes // attributeMap
                );
                
            } else {
                logger.error('User info endpoint returned error: ' + res.getStatusCode());
                throw new Auth.AuthProviderPluginException('Failed to retrieve user info: HTTP ' + res.getStatusCode());
            }
            
        } catch (System.CalloutException e) {
            RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('Mall_Ping_AuthProviderCustomPlugin');
            logger.error('Callout exception in getUserInfo: ' + e.getMessage());
            MallExceptionUtil.logAuthException('USERINFO_CALLOUT_ERROR', e.getMessage());
            throw new Auth.AuthProviderPluginException('Failed to retrieve user info: ' + e.getMessage());
            
        } catch (Exception e) {
            RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('Mall_Ping_AuthProviderCustomPlugin');
            logger.error('Unexpected exception in getUserInfo: ' + e.getMessage());
            logger.error('Stack trace: ' + e.getStackTraceString());
            MallExceptionUtil.logAuthException(e.getTypeName(), e.getMessage());
            throw new Auth.AuthProviderPluginException('Failed to retrieve user info: ' + e.getMessage());
        }
    }
}
