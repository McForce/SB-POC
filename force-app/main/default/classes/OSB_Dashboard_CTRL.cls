public with sharing class OSB_Dashboard_CTRL {

    private static final sbgplatform.rflib_Logger LOGGER = sbgplatform.rflib_LoggerUtil.getFactory().createLogger('OSB_Dashboard_CTRL');
    public static final String OBJ_NAME = 'Subscribed_Solutions__c';
    public static final String RT_APPLICATION = 'Subscribed_Applications';
    public static final String RT_SHORTCUTS = 'Subscribed_Shortcuts';
    public static final String SHORTCUTS_VALUE = 'Hide Shortcuts';

    /**
	* @description Checks if the user has been logged in for the first time for guided tour
	*
	* @return contact related to current user
	**/
    @AuraEnabled(cacheable=true)
    public static Contact getOnboardingDetails() {
        LOGGER.info('OSB_Dashboard_CTRL : getOnboardingDetails Check if user has been logged in for the first time');
        try{
            if (UTL_User.isLoggedInUser()) {
                LOGGER.info('OSB_Dashboard_CTRL : getOnboardingDetails Successful retrieving user information');
                return SEL_Contacts.newInstance().selectByUserId(new Set<Id>{UserInfo.getUserId()})[0];
            }
            return null;
        }
        catch(Exception e){
            LOGGER.error('OSB_Dashboard_CTRL : getOnboardingDetails  Exception logged: ',e);
            return null;
        }
        
    }

    /**
	* @description Gets a list of solutions that a user is subscribed to
	*
	* @return List<Knowledge__kav> register applications
	**/
    @AuraEnabled(Cacheable=true)
    public static List<Subscribed_Solutions__c> getRegisteredApplication() {
        LOGGER.info('OSB_Dashboard_CTRL : getRegisteredApplication Retrieve subscribed solution associated with contact of logged in ');
        try{
            Id contactId = SEL_Contacts.newInstance()
            .selectByUserId(new Set<Id>{ UserInfo.getUserId() })[0].Id;
            return SEL_SubscribedSolutions.newInstance().selectByContactId(new Set<Id>{contactId});
        }catch(Exception e){
            OSB_SRV_ActionFailureHandler.newInstance().handleError(e, OSB_Dashboard_CTRL.class.getName());
            LOGGER.error('OSB_Dashboard_CTRL : getOnboardingDetails  Exception logged: ',e);
            return null;
        }
       
    }

    /**
	* @description Gets a list of application subscribed solutions that a user is subscribed to
    * <br/>SFP-21026
	*
	* @return List<Knowledge__kav> registered applications
	**/
    @AuraEnabled(cacheable=true)
    public static List<Subscribed_Solutions__c> getRegisteredApplicationwithRecordType() {
        LOGGER.info('OSB_Dashboard_CTRL : getRegisteredApplicationwithRecordType Retrieve all subscribed solutions with application record type');
        Id contactId = SEL_Contacts.newInstance()
        .selectByUserId(new Set<Id>{ UserInfo.getUserId() })[0].Id;
        return SEL_SubscribedSolutions.newInstance().selectByContactIdAndRecordType(
            new Set<Id>{contactId},
            new Set<Id>{UTL_RecordType.getRecordTypeId(OBJ_NAME, RT_APPLICATION)}
        );
    }

    /**
	* @description Gets a list of shortcuts subscribed solutions that a user is subscribed to
    * <br/>SFP-21026
	*
	* @return List<Knowledge__kav> registered shortcuts
	**/
    @AuraEnabled(cacheable=true)
    public static List<Subscribed_Solutions__c> getRegisteredShortcutwithRecordType() {
        LOGGER.info('OSB_Dashboard_CTRL : getRegisteredApplicationwithRecordType Retrieve all subscribed solutions with shortcut record type');
        Id contactId = SEL_Contacts.newInstance()
        .selectByUserId(new Set<Id>{ UserInfo.getUserId() })[0].Id;
        return SEL_SubscribedSolutions.newInstance().selectByContactIdAndRecordType(
            new Set<Id>{contactId},
            new Set<Id>{UTL_RecordType.getRecordTypeId(OBJ_NAME, RT_SHORTCUTS)}
        );
    }

    /**
	* @description Sets the user contact Onboarding_Tour_Date__c to current date time
	*
	* @param contactId id of contact
	*
	**/
    @AuraEnabled(Cacheable=false)
    public static void setUserContactOnboardingDate(Id contactId) {
        LOGGER.info('OSB_Dashboard_CTRL : setUserContactOnboardingDate Setting the user has gone through onboarding');
        fflib_ISObjectUnitOfWork uow = ORG_Application.unitOfWork.newInstance();
        try{
            OSB_SRV_OnboardingHandler.newInstance().setUserContactOnboardingDate(new Set<Id>{contactId}, uow);
            uow.commitWork();
        }
        catch(Exception e){
            LOGGER.error('OSB_Dashboard_CTRL : setUserContactOnboardingDate  Exception logged: ',e);
        }
        LOGGER.info('OSB_Dashboard_CTRL : setUserContactOnboardingDate Successful update to onboarding date on users contact');

    }
    
	/**
	* @description Checks if user has any registered device
	*
	* @return Map<String,Map<String,Object>> that contains the device details  
    **/
    @AuraEnabled(Cacheable=true)
    public static Map<String,Map<String,Object>> hasRegisteredDevices(){
        LOGGER.info('OSB_Dashboard_CTRL : hasRegisteredDevices Checks if user has any registered device');
        Map<String,Map<String,Object>> deviceHeaders2Values = new Map<String,Map<String,Object>>();
        try {
            if(!Test.isRunningTest()){
                deviceHeaders2Values = OSB_SRV_NoknokIntegration.newInstance().getDeviceList();
            }else{
                String mockBody = '{\n'+
                '"statusCode": 4000,\n'+
                '"id": "i6cAnFM32oqiPyKVijAUcg",\n'+
                '"registrations": [\n'+
                '{\n'+
                '"device": {\n'+
                '"id": "MTCxZKm8Ybet4RExKx7UxF2X76di0csyf1zIR4uGKx8",\n'+
                '"info": "HMD+Global",\n'+
                '"deviceType": "android",\n'+
                '"os": "android 10",\n'+
                '"manufacturer": "HMD+Global",\n'+
                '"model": "Nokia+8.1"\n'+
                '},\n'+
                '"app": {\n'+
                '"id": "android:apk-key-hash:Bc9rEk16GTEpN3bbD+4zV/H3Msk",\n'+
                '"name": "android:com.noknok.android.passport2"\n'+
                '},\n'+
                '"authenticators": [\n'+
                '{\n'+
                '"description": "Android Fingerprint",\n'+
                '"createdTimeStamp": 1601907211708,\n'+
                '"handle": "WyJ1YWZfMS4wIiwiNGU0ZSM0MDE4IiwiRlB5S2tYU092WGZPeTAxMTNDbEpXWm9LU2NmazNkYVkxWGpJaTFkRjB0dyJd",\n'+
                '"status": 1\n'+
                '}\n'+
                ']\n'+
                '}\n'+
                '],\n'+
                '"additionalInfo": {}\n'+
                '}';
                Map<String, Object> mockResults = (Map<String, Object>) JSON.deserializeUntyped(mockBody);
                Map<String,String> statusAndIdMap = new Map<String,String>();
                statusAndIdMap.put('responseStatusCodeString',String.valueOf((Integer)mockResults.get('statusCode')));
                deviceHeaders2Values.put('statusAndIdMap',statusAndIdMap);
            }
            
        } catch (Exception e) {
            LOGGER.error('OSB_Dashboard_CTRL : hasRegisteredDevices  Exception logged: ',e);
            OSB_SRV_ActionFailureHandler.newInstance().handleError(e, OSB_Dashboard_CTRL.class.getName());
        }
        LOGGER.info('OSB_Dashboard_CTRL : hasRegisteredDevices Successful returned users devices');
        return deviceHeaders2Values; 
    }
    
    /**
	* @description Flags user's contact whether they want to see shortcuts or not
    * <br/>SFP-21026
	*
    *@param hideShortcuts boolean of hiding shortcuts or not
    *
	**/
    @AuraEnabled(Cacheable=false)
    public static void flagShortcuts(boolean hideShortcuts){
        LOGGER.info('OSB_Dashboard_CTRL : flagShortcuts Flag users contact on hiding shortcuts');
        Contact userContact = new Contact();
        fflib_ISObjectUnitOfWork uow = ORG_Application.unitOfWork.newInstance();
        try {
            if (UTL_User.isLoggedInUser()) {
                userContact = SEL_Contacts.newInstance()
                    .selectByUserId(new Set<Id>{ UserInfo.getUserId() })[0];
            }

            String manageFeature  = userContact.Manage_Site_Features__c;
            List<String> arrManageFeature = new List<String>();
            if(String.isNotBlank(manageFeature)){
                arrManageFeature = manageFeature.split(';');
            }
            Set<String> setManageFeature = new Set<String>(arrManageFeature);
    
            if(hideShortcuts == true){
                setManageFeature.add(SHORTCUTS_VALUE);
            }else{
                setManageFeature.remove(SHORTCUTS_VALUE);
            }
    
            List<String> updatedArrManageFeature = new List<String>(setManageFeature);
            userContact.Manage_Site_Features__c = string.join(updatedArrManageFeature,';');
    
            uow.registerDirty(userContact); 
            uow.commitWork();
        }catch(Exception e){
            LOGGER.error('OSB_Dashboard_CTRL : hasRegisteredDevices  Exception logged: ',e);
            OSB_SRV_ActionFailureHandler.newInstance().handleError(e, OSB_Dashboard_CTRL.class.getName());
        }
        LOGGER.info('OSB_Dashboard_CTRL : hasRegisteredDevices Successful updates users hide shortcuts value');

    }

    /**
	* @description Gets a list of solutions that a user is subscribed to
	* @param Id solutionId
    *@return List<Knowledge__kav> registered applications 
	**/
    @AuraEnabled(Cacheable=false)
    public static List<Subscribed_Solutions__c> getApplicationByContactIdAndSolutionId(Id solutionId) {
        LOGGER.info('OSB_Dashboard_CTRL : getRegisteredApplicationByUserIdAndSolutionId Retrieve subscribed solution associated with contact of logged in ');
        Id contactId = SEL_Contacts.newInstance()
        .selectByUserId(new Set<Id>{ UserInfo.getUserId() })[0].Id;
        return SEL_SubscribedSolutions.newInstance().selectByContactIdAndSolutionId(new set<Id>{solutionId}, new Set<Id>{contactId});
    }


}