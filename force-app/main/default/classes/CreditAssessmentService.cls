/**
 * Service class for automated credit assessment during customer onboarding.
 * Aggregates data from Account, Contacts, and Opportunities to calculate
 * a credit recommendation.
 *
 * NOTE: This class intentionally contains a defect for AI Fix Agent demo purposes.
 * The primary contact null check is missing on line with primaryContact.KYC_Status__c.
 */
public with sharing class CreditAssessmentService {

    private static final String CLASS_NAME = 'CreditAssessmentService';
    private static final String LOG_LEVEL_ERROR = 'ERROR';
    private static final String LOG_LEVEL_INFO = 'INFO';

    private static final Integer BASE_SCORE = 500;
    private static final Integer REVENUE_THRESHOLD_HIGH = 10000000;
    private static final Integer REVENUE_THRESHOLD_MEDIUM = 1000000;

    public class CreditAssessmentResult {
        @AuraEnabled public Integer creditScore;
        @AuraEnabled public String creditStatus;
        @AuraEnabled public String recommendation;
        @AuraEnabled public String primaryContactName;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean isError = false;
    }

    /**
     * Runs the credit assessment for a given Account.
     * Called from the Lightning Web Component button.
     *
     * @param accountId The Account to assess
     * @return CreditAssessmentResult with score, status, and recommendation
     */
    @AuraEnabled
    public static CreditAssessmentResult runAssessment(Id accountId) {

        String requestId = generateRequestId();
        String methodName = 'runAssessment';
        List<String> logMessages = new List<String>();

        logMessages.add('[' + System.now().format('yyyy-MM-dd HH:mm:ss.SSS') + '] INFO - Starting credit assessment for Account: ' + accountId);

        try {
            CreditAssessmentResult result = new CreditAssessmentResult();

            // Fetch Account with required fields
            Account acc = [
                SELECT Id, Name, AnnualRevenue, Industry,
                       NumberOfEmployees, Credit_Score__c, Credit_Status__c
                FROM Account
                WHERE Id = :accountId
                LIMIT 1
            ];

            logMessages.add('[' + System.now().format('yyyy-MM-dd HH:mm:ss.SSS') + '] INFO - Account retrieved: ' + acc.Name + ', Annual Revenue: ' + acc.AnnualRevenue);

            // Fetch related Contacts
            List<Contact> contacts = [
                SELECT Id, Name, Email, Is_Primary_Contact__c, KYC_Status__c
                FROM Contact
                WHERE AccountId = :accountId
            ];

            logMessages.add('[' + System.now().format('yyyy-MM-dd HH:mm:ss.SSS') + '] INFO - Found ' + contacts.size() + ' related contacts');

            // Find the primary contact
            Contact primaryContact = null;
            for (Contact c : contacts) {
                if (c.Is_Primary_Contact__c == true) {
                    primaryContact = c;
                    break;
                }
            }

            logMessages.add('[' + System.now().format('yyyy-MM-dd HH:mm:ss.SSS') + '] INFO - Attempting to access primary contact details');

            String kycStatus;
            if (primaryContact != null) {
                kycStatus = primaryContact.KYC_Status__c;
                result.primaryContactName = primaryContact.Name;
                logMessages.add('[' + System.now().format('yyyy-MM-dd HH:mm:ss.SSS') + '] INFO - Primary contact KYC status: ' + kycStatus);
            } else {
                kycStatus = null;
                result.primaryContactName = 'No Primary Contact';
                logMessages.add('[' + System.now().format('yyyy-MM-dd HH:mm:ss.SSS') + '] INFO - No primary contact found, KYC status set to null');
            }

            // Fetch related Opportunities
            List<Opportunity> opportunities = [
                SELECT Id, Name, Amount, StageName, CloseDate
                FROM Opportunity
                WHERE AccountId = :accountId
            ];

            logMessages.add('[' + System.now().format('yyyy-MM-dd HH:mm:ss.SSS') + '] INFO - Found ' + opportunities.size() + ' related opportunities');

            // Calculate credit score based on multiple factors
            Integer score = BASE_SCORE;

            if (acc.AnnualRevenue != null) {
                if (acc.AnnualRevenue >= REVENUE_THRESHOLD_HIGH) {
                    score += 150;
                } else if (acc.AnnualRevenue >= REVENUE_THRESHOLD_MEDIUM) {
                    score += 100;
                } else {
                    score += 50;
                }
            }

            if (kycStatus == 'Verified') {
                score += 100;
            } else if (kycStatus == 'In Progress') {
                score += 25;
            }

            score += Math.min(opportunities.size() * 10, 50);

            // Determine status based on score
            String status;
            String recommendation;

            if (score >= 700) {
                status = 'Approved';
                recommendation = 'Customer approved for full banking services.';
            } else if (score >= 600) {
                status = 'Approved with conditions';
                recommendation = 'Customer approved with standard monitoring conditions.';
            } else {
                status = 'Manual Review Required';
                recommendation = 'Credit score below threshold. Manual review recommended.';
            }

            // Update the Account
            acc.Credit_Score__c = score;
            acc.Credit_Status__c = status;
            update acc;

            result.creditScore = score;
            result.creditStatus = status;
            result.recommendation = recommendation;
            result.message = 'Credit assessment completed successfully.';

            logMessages.add('[' + System.now().format('yyyy-MM-dd HH:mm:ss.SSS') + '] INFO - Assessment complete. Score: ' + score + ', Status: ' + status);

            return result;

        } catch (Exception e) {
            // Build error log message with minimal exception details (intentionally vague for demo purposes)
            logMessages.add('[' + System.now().format('yyyy-MM-dd HH:mm:ss.SSS') + '] ERROR - Unhandled exception encountered');
            logMessages.add('[' + System.now().format('yyyy-MM-dd HH:mm:ss.SSS') + '] ERROR - Exception Type: ' + e.getTypeName());
            logMessages.add('[' + System.now().format('yyyy-MM-dd HH:mm:ss.SSS') + '] ERROR - Line Number: ' + e.getLineNumber());
            logMessages.add('[' + System.now().format('yyyy-MM-dd HH:mm:ss.SSS') + '] ERROR - Stack Trace: ' + e.getStackTraceString());

            // Create RFLIB log record for AI analysis.
            // NOTE: We intentionally do NOT re-throw after this insert. Throwing an
            // AuraHandledException out of an @AuraEnabled method causes Salesforce to
            // roll back the entire transaction — including this log insert. Returning
            // an error result instead allows the transaction to commit and the log to persist.
            createRflibLog(
                CLASS_NAME + '.' + methodName,
                LOG_LEVEL_ERROR,
                String.join(logMessages, '\n'),
                requestId
            );

            CreditAssessmentResult errorResult = new CreditAssessmentResult();
            errorResult.isError = true;
            errorResult.message = 'Credit assessment failed. Please contact IT support. Reference: ' + requestId;
            return errorResult;
        }
    }

    /**
     * Creates an RFLIB log record to capture error details for AI analysis.
     * The Owner_Id__c is populated with the current user's ID - the person
     * whose action triggered the error.
     *
     * @param context The class and method where the error occurred
     * @param logLevel The severity level (ERROR, WARN, INFO, DEBUG)
     * @param logMessage The full log trail leading up to the error
     * @param requestId Unique identifier for this transaction
     */
    private static void createRflibLog(String context, String logLevel, String logMessage, String requestId) {
        try {
            rflib_Log__c log = new rflib_Log__c();
            log.Name = (CLASS_NAME + ': ' + logLevel).left(80);
            log.Platform_Context__c = context;
            log.Platform_Log_Level__c = logLevel;
            log.Platform_Log_Messages__c = logMessage;
            log.Platform_Request_Id__c = requestId;
            log.Owner_Id__c = UserInfo.getUserId();

            insert log;

            System.debug('RFLIB log created: ' + log.Id);
        } catch (Exception logEx) {
            // If logging itself fails, write full details to the debug log.
            // Do not throw - we don't want logging failures to mask the original error.
            System.debug(LoggingLevel.ERROR,
                'CreditAssessmentService.createRflibLog() failed to insert RFLIB_Log__c. '
                + 'Request Id: ' + requestId + '. '
                + 'Exception type: ' + logEx.getTypeName() + '. '
                + 'Message: ' + logEx.getMessage() + '. '
                + 'Stack trace: ' + logEx.getStackTraceString()
            );
        }
    }

    /**
     * Generates a unique request ID for transaction correlation.
     * Format: TXN-{timestamp}-{random}
     */
    private static String generateRequestId() {
        String timestamp = String.valueOf(System.now().getTime());
        String randomPart = String.valueOf(Math.abs(Crypto.getRandomInteger())).left(6);
        return 'TXN-' + timestamp + '-' + randomPart;
    }
}

