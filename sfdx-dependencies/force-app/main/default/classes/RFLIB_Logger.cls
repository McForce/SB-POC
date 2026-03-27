/**
 * @description RFLIB_Logger stub class for demo/POC purposes.
 *              For production, install the full RFLIB package from:
 *              https://github.com/j-fischer/rflib or AppExchange.
 * 
 *              This stub provides the minimum interface required for 
 *              the OneHub POC classes to compile and deploy.
 */
public class RFLIB_Logger {
    
    private String context;
    
    public RFLIB_Logger(String context) {
        this.context = context;
    }
    
    /**
     * @description Log an info-level message
     * @param message The message to log
     */
    public void info(String message) {
        System.debug(LoggingLevel.INFO, '[' + context + '] INFO: ' + message);
    }
    
    /**
     * @description Log a debug-level message
     * @param message The message to log
     */
    public void debug(String message) {
        System.debug(LoggingLevel.DEBUG, '[' + context + '] DEBUG: ' + message);
    }
    
    /**
     * @description Log a warn-level message
     * @param message The message to log
     */
    public void warn(String message) {
        System.debug(LoggingLevel.WARN, '[' + context + '] WARN: ' + message);
    }
    
    /**
     * @description Log an error-level message
     * @param message The message to log
     */
    public void error(String message) {
        System.debug(LoggingLevel.ERROR, '[' + context + '] ERROR: ' + message);
    }
    
    /**
     * @description Log an error-level message with exception details
     * @param message The message to log
     * @param ex The exception to include
     */
    public void error(String message, Exception ex) {
        System.debug(LoggingLevel.ERROR, '[' + context + '] ERROR: ' + message + 
            '\nException: ' + ex.getMessage() + 
            '\nStack Trace: ' + ex.getStackTraceString());
    }
    
    /**
     * @description Log a fatal-level message
     * @param message The message to log
     */
    public void fatal(String message) {
        System.debug(LoggingLevel.ERROR, '[' + context + '] FATAL: ' + message);
    }
    
    /**
     * @description Log a fatal-level message with exception details
     * @param message The message to log
     * @param ex The exception to include
     */
    public void fatal(String message, Exception ex) {
        System.debug(LoggingLevel.ERROR, '[' + context + '] FATAL: ' + message + 
            '\nException: ' + ex.getMessage() + 
            '\nStack Trace: ' + ex.getStackTraceString());
    }
}
