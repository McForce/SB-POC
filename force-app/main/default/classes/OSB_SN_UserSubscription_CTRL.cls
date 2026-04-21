public with sharing class OSB_SN_UserSubscription_CTRL {
    
    public static Map<String, Object> getUserPreferences(String userId) {
        // This method retrieves the user's notification and subscription preferences
        // from the Subscribed_Solutions__c custom object in Salesforce.
        //
        // It is called by getUserSubscription() to populate the user's preference 
        // settings when the OneHub dashboard loads.
        
        RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('OSB_SN_UserSubscription_CTRL');
        
        try {
            logger.info('getUserPreferences called for userId: ' + userId);
            
            // ====================================================================
            // QUERY: Retrieve the user's subscription preferences
            // ====================================================================
            // This query looks for Subscribed_Solutions__c records owned by the 
            // current user. The expectation is that at least one record exists
            // after the user completes registration and onboarding.
            
            List<Subscribed_Solutions__c> userPrefs = [
                SELECT Id, Name, Solution_Name__c, Notification_Enabled__c,
                       Email_Alerts__c, Push_Notifications__c, Frequency__c,
                       Last_Modified_Date__c
                FROM Subscribed_Solutions__c
                WHERE OwnerId = :userId
                ORDER BY Solution_Name__c ASC
            ];
            
            // FIX: Check if the list is empty before accessing index 0
            // If no subscription records exist, return a default empty map
            // to prevent "List index out of bounds: 0" exception
            if (userPrefs.isEmpty()) {
                logger.info('No subscription preferences found for userId: ' + userId + '. Returning default empty preferences.');
                Map<String, Object> defaultResult = new Map<String, Object>();
                defaultResult.put('preferenceId', null);
                defaultResult.put('solutionName', null);
                defaultResult.put('notificationsEnabled', false);
                defaultResult.put('emailAlerts', false);
                defaultResult.put('pushNotifications', false);
                defaultResult.put('frequency', new Map<String, Object>());
                return defaultResult;
            }
            
            Subscribed_Solutions__c primaryPref = userPrefs[0];
            
            // FIX: Check if Frequency__c is null or empty before deserializing
            // to prevent "Script-thrown exception" from invalid JSON
            Map<String, Object> frequencySettings = new Map<String, Object>();
            if (String.isNotBlank(primaryPref.Frequency__c)) {
                try {
                    frequencySettings = (Map<String, Object>) JSON.deserializeUntyped(primaryPref.Frequency__c);
                } catch (Exception jsonEx) {
                    logger.warn('Invalid JSON in Frequency__c field for preferenceId: ' + primaryPref.Id + '. Using empty frequency settings.');
                    frequencySettings = new Map<String, Object>();
                }
            }
            
            // Build the response map
            Map<String, Object> result = new Map<String, Object>();
            result.put('preferenceId', primaryPref.Id);
            result.put('solutionName', primaryPref.Solution_Name__c);
            result.put('notificationsEnabled', primaryPref.Notification_Enabled__c);
            result.put('emailAlerts', primaryPref.Email_Alerts__c);
            result.put('pushNotifications', primaryPref.Push_Notifications__c);
            result.put('frequency', frequencySettings);
            
            logger.info('Successfully retrieved preferences for userId: ' + userId);
            return result;
            
        } catch (Exception e) {
            logger.error('OSB_SN_UserSubscription_CTRL : getUserPreferences Exception logged: ' +
                '\nMessage: ' + e.getMessage() +
                '\nStracktrace: ' + e.getStackTraceString());
            
            throw e;
        }
    }
    
    public static Map<String, Object> getUserSubscription() {
        // This method is the main entry point called by the OneHub Experience Cloud
        // Lightning Web Component (LWC) when the user's dashboard loads.
        //
        // It retrieves the current user's subscription and notification preferences
        // by calling getUserPreferences() with the current user's Id.
        //
        // This is an @AuraEnabled method exposed to the front-end.
        
        RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('OSB_SN_UserSubscription_CTRL');
        
        try {
            logger.info('getUserSubscription called');
            
            // Get the current authenticated user's Id
            String currentUserId = UserInfo.getUserId();
            logger.info('Current user Id: ' + currentUserId);
            
            // Retrieve user profile information for context
            User currentUser = [
                SELECT Id, Name, Email, Profile.Name, ContactId, Contact.AccountId
                FROM User
                WHERE Id = :currentUserId
                LIMIT 1
            ];
            
            logger.info('User profile: ' + currentUser.Profile.Name);
            
            Map<String, Object> preferences = getUserPreferences(currentUserId);
            
            // Build the full subscription response
            Map<String, Object> response = new Map<String, Object>();
            response.put('userId', currentUserId);
            response.put('userName', currentUser.Name);
            response.put('userEmail', currentUser.Email);
            response.put('preferences', preferences);
            response.put('lastAccessed', System.now());
            
            logger.info('Successfully retrieved subscription for user: ' + currentUser.Name);
            return response;
            
        } catch (Exception e) {
            logger.error('OSB_SN_UserSubscription_CTRL : getUserSubscription Exception logged: ' +
                '\nMessage: ' + e.getMessage() +
                '\nStracktrace: ' + e.getStackTraceString());
            
            throw new AuraHandledException(
                'Unable to retrieve your subscription preferences. Please contact support.'
            );
        }
    }
    
    public static void saveUserPreferences(String userId, Map<String, Object> newPreferences) {
        // This method saves or updates user notification and subscription preferences.
        //
        // It is called when a user modifies their notification settings on the 
        // OneHub dashboard (e.g. enabling/disabling email alerts, changing frequency).
        //
        // IMPORTANT: This method first calls getUserPreferences() to retrieve
        // the existing preference record before applying updates. This is why
        // errors in getUserPreferences() appear in the logs with the context
        // "saveUserPreferences Exception logged" — the save flow triggers the
        // read flow, and the read flow fails.
        
        RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('OSB_SN_UserSubscription_CTRL');
        
        try {
            logger.info('saveUserPreferences called for userId: ' + userId);
            logger.info('New preferences: ' + JSON.serialize(newPreferences));
            
            Map<String, Object> existingPreferences = getUserPreferences(userId);
            
            // FIX: Check if preferenceId is null (no existing record)
            // If null, create a new record instead of attempting an update
            String preferenceId = (String) existingPreferences.get('preferenceId');
            
            if (preferenceId == null) {
                // Create new preference record
                Subscribed_Solutions__c newPref = new Subscribed_Solutions__c(
                    OwnerId = userId,
                    Notification_Enabled__c = (Boolean) newPreferences.get('notificationsEnabled'),
                    Email_Alerts__c = (Boolean) newPreferences.get('emailAlerts'),
                    Push_Notifications__c = (Boolean) newPreferences.get('pushNotifications'),
                    Frequency__c = JSON.serialize(newPreferences.get('frequency'))
                );
                
                insert newPref;
                logger.info('Successfully created new preferences for userId: ' + userId);
            } else {
                // Update existing preference record
                Subscribed_Solutions__c prefToUpdate = new Subscribed_Solutions__c(
                    Id = preferenceId,
                    Notification_Enabled__c = (Boolean) newPreferences.get('notificationsEnabled'),
                    Email_Alerts__c = (Boolean) newPreferences.get('emailAlerts'),
                    Push_Notifications__c = (Boolean) newPreferences.get('pushNotifications'),
                    Frequency__c = JSON.serialize(newPreferences.get('frequency'))
                );
                
                update prefToUpdate;
                logger.info('Successfully updated preferences for userId: ' + userId);
            }
            
        } catch (Exception e) {
            logger.error('OSB_SN_UserSubscription_CTRL : saveUserPreferences Exception logged: ' +
                '\nMessage: ' + e.getMessage() +
                '\nStracktrace: ' + e.getStackTraceString());
            
            throw new AuraHandledException(
                'Unable to save your preferences. Please try again or contact support.'
            );
        }
    }
}
