public with sharing class OSB_SN_UserSubscription_CTRL {

    public static Map<String, Object> getUserPreferences(String userId) {
        RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('OSB_SN_UserSubscription_CTRL');

        try {
            logger.info('getUserPreferences called for userId: ' + userId);

            List<Subscribed_Solutions__c> userPrefs = [
                SELECT Id, Name, Solution_Name__c, Notification_Enabled__c,
                       Email_Alerts__c, Push_Notifications__c, Frequency__c,
                       Last_Modified_Date__c
                FROM Subscribed_Solutions__c
                WHERE OwnerId = :userId
                ORDER BY Solution_Name__c ASC
            ];

            // ====================================================================
            // FIX FOR LINE 25: List index out of bounds: 0
            // ====================================================================
            //
            // ORIGINAL PROBLEM:
            // The code directly accessed userPrefs[0] without checking size.
            // For newly registered users, or users whose preference records were
            // not created during onboarding (e.g. failed registration flow or
            // data migration gap), this query returns an empty list and
            // Salesforce throws: "List index out of bounds: 0"
            //
            // FIX: Check isEmpty() before accessing index 0.
            // Return a safe default map if no records exist so callers
            // (getUserSubscription, saveUserPreferences) can handle the
            // no-record case gracefully without an exception.

            if (userPrefs.isEmpty()) {
                logger.info('No subscription preference records found for userId: ' + userId + '. Returning defaults.');
                Map<String, Object> defaults = new Map<String, Object>();
                defaults.put('preferenceId', null);
                defaults.put('solutionName', null);
                defaults.put('notificationsEnabled', false);
                defaults.put('emailAlerts', false);
                defaults.put('pushNotifications', false);
                defaults.put('frequency', new Map<String, Object>());
                return defaults;
            }

            Subscribed_Solutions__c primaryPref = userPrefs[0];

            // ====================================================================
            // FIX FOR LINE 28: Script-thrown exception (null / invalid JSON)
            // ====================================================================
            //
            // ORIGINAL PROBLEM:
            // JSON.deserializeUntyped() was called directly on Frequency__c
            // without a null or blank check. If the field was null, empty, or
            // contained malformed JSON, Salesforce threw a Script-thrown exception.
            // This was the second error pattern seen in RFLIB logs with stack trace
            // pointing to getUserPreferences line 28.
            //
            // FIX: Guard with String.isNotBlank() before deserialising, and wrap
            // the call in its own try/catch so a bad value falls back to an
            // empty map rather than propagating an unhandled exception.

            Map<String, Object> frequencySettings = new Map<String, Object>();
            if (String.isNotBlank(primaryPref.Frequency__c)) {
                try {
                    frequencySettings = (Map<String, Object>) JSON.deserializeUntyped(primaryPref.Frequency__c);
                } catch (Exception jsonEx) {
                    logger.warn('getUserPreferences: Frequency__c contains invalid JSON for userId: ' + userId + '. Defaulting to empty map.');
                }
            }

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
        RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('OSB_SN_UserSubscription_CTRL');

        try {
            logger.info('getUserSubscription called');

            String currentUserId = UserInfo.getUserId();
            logger.info('Current user Id: ' + currentUserId);

            User currentUser = [
                SELECT Id, Name, Email, Profile.Name, ContactId, Contact.AccountId
                FROM User
                WHERE Id = :currentUserId
                LIMIT 1
            ];

            logger.info('User profile: ' + currentUser.Profile.Name);

            Map<String, Object> preferences = getUserPreferences(currentUserId);

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
        RFLIB_Logger logger = RFLIB_LoggerUtil.getLogger('OSB_SN_UserSubscription_CTRL');

        try {
            logger.info('saveUserPreferences called for userId: ' + userId);
            logger.info('New preferences: ' + JSON.serialize(newPreferences));

            Map<String, Object> existingPreferences = getUserPreferences(userId);

            String preferenceId = (String) existingPreferences.get('preferenceId');

            Subscribed_Solutions__c prefToUpdate = new Subscribed_Solutions__c(
                Id = preferenceId,
                Notification_Enabled__c = (Boolean) newPreferences.get('notificationsEnabled'),
                Email_Alerts__c = (Boolean) newPreferences.get('emailAlerts'),
                Push_Notifications__c = (Boolean) newPreferences.get('pushNotifications'),
                Frequency__c = JSON.serialize(newPreferences.get('frequency'))
            );

            update prefToUpdate;

            logger.info('Successfully updated preferences for userId: ' + userId);

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
