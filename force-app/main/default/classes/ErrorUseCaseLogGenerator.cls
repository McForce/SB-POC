public class ErrorUseCaseLogGenerator {
    
    @InvocableMethod(
        label='Generate RFLIB Logs by Error Use Case' 
        description='Creates RFLIB_Log__c records from ErrorUseCases static resource based on selected use case'
    )
    public static List<GenerateLogsResult> generateErrorUseCaseLogs(List<GenerateLogsRequest> requests) {
        List<GenerateLogsResult> results = new List<GenerateLogsResult>();
        
        if (requests == null || requests.isEmpty()) {
            GenerateLogsResult result = new GenerateLogsResult();
            result.success = false;
            result.message = 'Error: No request provided';
            result.logsCreatedCount = 0;
            results.add(result);
            return results;
        }
        
        GenerateLogsRequest request = requests[0];
        GenerateLogsResult result = new GenerateLogsResult();
        
        try {
            // Parse CSV static resource
            StaticResource sr = [SELECT Body FROM StaticResource WHERE Name = 'ErrorUseCases' LIMIT 1];
            String csvContent = sr.Body.toString();
            
            // Parse CSV and filter by use case
            List<RFLIB_Log__c> logsToCreate = parseCSVAndCreateLogs(
                csvContent, 
                request.selectedUseCase
            );
            
            // Bulk insert
            if (!logsToCreate.isEmpty()) {
                insert logsToCreate;
                result.success = true;
                result.logsCreatedCount = logsToCreate.size();
                result.message = 'Successfully created ' + logsToCreate.size() + ' log records for use case: ' + request.selectedUseCase;
            } else {
                result.success = false;
                result.logsCreatedCount = 0;
                result.message = 'No log records found for use case: ' + request.selectedUseCase;
            }
            
        } catch (QueryException qe) {
            result.success = false;
            result.logsCreatedCount = 0;
            result.message = 'Error: Static resource "ErrorUseCases" not found. ' + qe.getMessage();
        } catch (DmlException dme) {
            result.success = false;
            result.logsCreatedCount = 0;
            result.message = 'Error creating log records: ' + dme.getMessage();
        } catch (Exception e) {
            result.success = false;
            result.logsCreatedCount = 0;
            result.message = 'Error: ' + e.getMessage();
        }
        
        results.add(result);
        return results;
    }
    
    /**
     * Parse CSV and create RFLIB_Log__c records for the selected use case
     */
    private static List<RFLIB_Log__c> parseCSVAndCreateLogs(String csvContent, String selectedUseCase) {
        List<RFLIB_Log__c> logs = new List<RFLIB_Log__c>();
        
        // Split by line, handling quoted fields
        List<String> lines = csvContent.split('\n');
        
        // Skip header row (index 0)
        for (Integer i = 1; i < lines.size(); i++) {
            String line = lines[i].trim();
            
            // Skip empty lines
            if (String.isBlank(line)) {
                continue;
            }
            
            // Parse CSV line
            List<String> fields = parseCSVLine(line);
            
            // Validate fields array has all required columns (8 columns)
            if (fields.size() < 8) {
                continue;
            }
            
            // Check if this row matches the selected use case
            String useCaseFromCSV = fields[0].trim();
            
            if (useCaseFromCSV == selectedUseCase) {
                try {
                    // Extract fields from CSV
                    String name = fields[1].trim();
                    String ownerId = fields[2].trim();
                    String createdDateString = fields[3].trim();
                    String logLevel = fields[4].trim();
                    String context = fields[5].trim();
                    String requestId = fields[6].trim();
                    String logMessages = fields[7].trim();
                    
                    // Parse DateTime
                    DateTime createdDate = DateTime.valueOf(createdDateString.replace('T', ' ').replace('+0000', '').replace('.000', ''));
                    
                    // Create RFLIB_Log__c record
                    RFLIB_Log__c log = new RFLIB_Log__c(
                        Name = name,
                        Owner_Id__c = ownerId,
                        Created_Date_Sim__c = createdDate,
                        Platform_Log_Level__c = logLevel,
                        Platform_Context__c = context,
                        Platform_Request_Id__c = requestId,
                        Platform_Log_Messages__c = logMessages
                    );
                    
                    logs.add(log);
                    
                } catch (Exception e) {
                    System.debug('Error parsing CSV row ' + i + ': ' + e.getMessage());
                    continue;
                }
            }
        }
        
        return logs;
    }
    
    /**
     * Parse a CSV line, handling quoted fields and commas within quotes
     * CSV Format: Field1,Field2,"Field with, comma",Field4
     */
    private static List<String> parseCSVLine(String line) {
        List<String> result = new List<String>();
        String current = '';
        Boolean inQuotes = false;
        
        for (Integer i = 0; i < line.length(); i++) {
            String currentChar = line.substring(i, i + 1);
            
            if (currentChar == '"') {
                // Toggle quote state
                inQuotes = !inQuotes;
                current += currentChar;  // Keep the quote in the field
            } else if (currentChar == ',' && !inQuotes) {
                // Found a field separator (comma outside quotes)
                result.add(current.trim());
                current = '';
            } else {
                current += currentChar;
            }
        }
        
        // Add the last field
        result.add(current.trim());
        
        // Remove quotes from quoted fields
        for (Integer i = 0; i < result.size(); i++) {
            String field = result[i];
            if (field.startsWith('"') && field.endsWith('"')) {
                field = field.substring(1, field.length() - 1);
            }
            result[i] = field;
        }
        
        return result;
    }
    

    
    /**
     * Input class for generating logs
     */
    public class GenerateLogsRequest {
        @InvocableVariable(label='Selected Use Case' required=true)
        public String selectedUseCase;
    }
    
    /**
     * Result class for generating logs
     */
    public class GenerateLogsResult {
        @InvocableVariable(label='Success')
        public Boolean success;
        
        @InvocableVariable(label='Message')
        public String message;
        
        @InvocableVariable(label='Logs Created Count')
        public Integer logsCreatedCount;
    }
}