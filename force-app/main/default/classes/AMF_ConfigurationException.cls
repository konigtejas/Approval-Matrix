/**
 * Raised when the configuration validator finds one or more invalid active
 * matrix rules. A post-deploy pipeline calls validateOrThrow(), so this error
 * makes the pipeline fail before a bad rule can reach submit time.
 */
public class AMF_ConfigurationException extends Exception {
}
