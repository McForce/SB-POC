/**
 * @description RFLIB_LoggerUtil stub class for demo/POC purposes.
 *              For production, install the full RFLIB package from:
 *              https://github.com/j-fischer/rflib or AppExchange.
 * 
 *              This utility class provides factory methods for creating
 *              RFLIB_Logger instances.
 */
public class RFLIB_LoggerUtil {
    
    /**
     * @description Creates a new logger instance for the specified context
     * @param context The logging context (typically the class name)
     * @return A new RFLIB_Logger instance
     */
    public static RFLIB_Logger getLogger(String context) {
        return new RFLIB_Logger(context);
    }
    
    /**
     * @description Creates a new logger instance using the calling class type
     * @param classType The Type of the calling class
     * @return A new RFLIB_Logger instance
     */
    public static RFLIB_Logger getLogger(Type classType) {
        return new RFLIB_Logger(classType.getName());
    }
}
