// The Claude connector's one-time org setup (M16, architecture §7's M16 note).
//
//   sf apex run --file scripts/setup-mcp.apex -o <alias>
//
// Seeds AMF_Mcp_Settings__c.Preview_Key__c, the key AMF_McpSupport signs every preview with, so
// that submit_for_approval submits only a record its user has just previewed. Idempotent: an
// existing key is kept, because replacing it invalidates every preview not yet submitted. To
// rotate the key deliberately, clear the field in Setup -> Custom Settings and run this again.
//
// The outcome is logged at ERROR level so that it shows in the CLI's default log output.

AMF_Mcp_Settings__c settings = AMF_Mcp_Settings__c.getOrgDefaults();

if (String.isBlank(settings.Preview_Key__c)) {
    settings.Preview_Key__c = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
    upsert settings;
    System.debug(LoggingLevel.ERROR, 'Claude connector: preview key created.');
} else {
    System.debug(LoggingLevel.ERROR, 'Claude connector: preview key already set, left unchanged.');
}
