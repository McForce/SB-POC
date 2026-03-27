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
            //
            // PROBLEM: For newly registered users, or users whose preference
            // records were not created during onboarding (e.g. due to a failed
            // registration flow or data migration gap), this query returns an
            // empty list.

            List<Subscribed_Solutions__c> userPrefs = [
                SELECT Id, Name, Solution_Name__c, Notification_Enabled__c,
                       Email_Alerts__c, Push_Notifications__c, Frequency__c,
                       Last_Modified_Date__c
                FROM Subscribed_Solutions__c
                WHERE OwnerId = :userId
                ORDER BY Solution_Name__c ASC
            ];

            // ====================================================================
            // LINE 25: THE PROBLEM — List index out of bounds: 0
            // ====================================================================
            //
            // WHAT HAPPENS:
            // 1. The SOQL query above returns an empty List (size = 0)
            // 2. The code directly accesses userPrefs[0] without checking size
            // 3. Salesforce throws: "List index out of bounds: 0"
            // 4. Stack trace shows: "line 25, column 1"
            //
            // WHY THIS OCCURS:
            // - User completed authentication (Ping + NokNok MFA) successfully
            // - User session is established in OneHub (Experience Cloud)
            // - OneHub dashboard loads and calls getUserSubscription()
            // - getUserSubscription() calls this method to load preferences
            // - But the user has NO Subscribed_Solutions__c records
            //
            // ROOT CAUSE:
            // The code assumes that every authenticated user has at least one
            // subscription preference record. This assumption fails when:
            //   a) User is newly registered and onboarding did not create defaults
            //   b) Preference records were deleted or not migrated
            //   c) The user's OwnerId does not match the queried field
            //
            // BETTER APPROACH:
            // 1. Check if userPrefs.isEmpty() before accessing index 0
            // 2. Return a default preference map if no records exist
            // 3. Create default Subscribed_Solutions__c records on first login

            Subscribed_Solutions__c primaryPref = userPrefs[0]; // LINE 25: FAILS HERE

            // ====================================================================
            // LINE 28: SECONDARY FAILURE — Script-thrown exception
            // ====================================================================
            //
            // WHAT HAPPENS:
            // If line 25 somehow succeeds (e.g. a record exists but is malformed),
            // the code attempts to deserialise the Frequency__c field as JSON.
            // If the field is null, empty, or contains invalid JSON, the
            // JSON.deserializeUntyped() call throws a Script-thrown exception.
            //
            // This is the SECOND error pattern seen in the logs:
            // "saveUserPreferences Exception logged: Message: Script-thrown exception"
            // "Stracktrace: Class.OSB_SN_UserSubscription_CTRL.getUserPreferences: line 28"
            //
            // WHY THE LOG SAYS "saveUserPreferences":
            // The RFLIB logger context is set at the method level. When this method
            // is called from the saveUserPreferences flow (which first reads existing
            // preferences before saving), the log message prefix reflects the calling
            // context. The actual failure is still in getUserPreferences at line 28.

            Map<String, Object> frequencySettings = (Map<String, Object>) JSON.deserializeUntyped(
                primaryPref.Frequency__c  // LINE 28: FAILS HERE if null or invalid JSON
            );

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
            // ====================================================================
            // EXCEPTION HANDLING — Generates the RFLIB log entries we see
            // ====================================================================
            //
            // When line 25 fails with "List index out of bounds: 0", or
            // when line 28 fails with "Script-thrown exception",
            // this catch block logs the error via RFLIB.
            //
            // The RFLIB log entry created here is what appears in the
            // Platform_Log_Messages__c field of the RFLIB_Log__c record:
            //
            // "OSB_SN_UserSubscription_CTRL : getUserPreferences Exception logged:
            //  Message: List index out of bounds: 0
            //  Stracktrace: Class.OSB_SN_UserSubscription_CTRL.getUserPreferences: line 25, column 1
            //  Class.OSB_SN_UserSubscription_CTRL.getUserSubscription: line 42, column 1"

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

            // ====================================================================
            // LINE 42: CALLS getUserPreferences — WHERE THE ERROR ORIGINATES
            // ====================================================================
            //
            // WHAT HAPPENS:
            // 1. getUserSubscription() calls getUserPreferences() at line 42
            // 2. getUserPreferences() executes the SOQL query
            // 3. If no Subscribed_Solutions__c records exist for this user:
            //    - getUserPreferences() throws "List index out of bounds: 0" at line 25
            //    - The exception propagates back to this method
            //    - Stack trace shows both: line 25 (origin) and line 42 (caller)
            //
            // THIS IS WHY THE STACK TRACE SHOWS TWO LINES:
            // "Class.OSB_SN_UserSubscription_CTRL.getUserPreferences: line 25, column 1"
            // "Class.OSB_SN_UserSubscription_CTRL.getUserSubscription: line 42, column 1"
            //
            // The error originates at line 25, but the call is made at line 42.

            Map<String, Object> preferences = getUserPreferences(currentUserId); // LINE 42

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

            // ====================================================================
            // FIRST: Retrieve existing preferences to determine update vs insert
            // ====================================================================
            //
            // THIS IS WHERE THE ERROR CHAIN BEGINS FOR THE "saveUserPreferences" LOGS:
            //
            // 1. saveUserPreferences() calls getUserPreferences() to get existing state
            // 2. getUserPreferences() queries Subscribed_Solutions__c
            // 3. If no records exist → "List index out of bounds: 0" at line 25
            // 4. If record exists but Frequency__c is null → "Script-thrown exception" at line 28
            // 5. Exception propagates back here
            // 6. RFLIB logs: "saveUserPreferences Exception logged: Message: ..."
            //    with stack trace showing getUserPreferences line 25 or 28

            Map<String, Object> existingPreferences = getUserPreferences(userId);

            // If we get here, existing preferences were found — update them
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
            // ====================================================================
            // THIS CATCH BLOCK GENERATES THE "saveUserPreferences" LOG ENTRIES
            // ====================================================================
            //
            // When getUserPreferences() fails inside this method, the RFLIB log
            // message is prefixed with "saveUserPreferences" because that is the
            // calling context. The stack trace still shows:
            //
            // "Class.OSB_SN_UserSubscription_CTRL.getUserPreferences: line 25, column 1"
            // "Class.OSB_SN_UserSubscription_CTRL.getUserSubscription: line 42, column 1"
            //
            // This can be confusing because the log says "saveUserPreferences" but
            // the stack trace references "getUserSubscription". This is because both
            // getUserSubscription() and saveUserPreferences() call getUserPreferences(),
            // and the RFLIB logging captures the full call chain.

            logger.error('OSB_SN_UserSubscription_CTRL : saveUserPreferences Exception logged: ' +
                '\nMessage: ' + e.getMessage() +
                '\nStracktrace: ' + e.getStackTraceString());

            throw new AuraHandledException(
                'Unable to save your preferences. Please try again or contact support.'
            );
        }
    }
}
