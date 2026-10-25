/*
 * Approval Matrix post-deploy configuration gate.
 *
 * Run after the metadata deploy, as an administrator holding
 * Approval_Matrix_Admin:
 *
 *   sf apex run --file scripts/validate-config.apex --target-org amf-dev
 *
 * An AMF_ConfigurationException is deliberately left uncaught. It gives the
 * CLI a failing run and prints every active-rule defect in one report.
 */
AMF_ConfigValidator.validateOrThrow();
System.debug(LoggingLevel.ERROR, 'Approval Matrix configuration is valid.');
