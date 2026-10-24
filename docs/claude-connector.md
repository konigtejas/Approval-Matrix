# The Claude connector: the approval matrix in Claude

Since M16, Claude can work with the approval matrix directly: in claude.ai, Claude Desktop, the
Claude mobile apps and Claude Code. Ask it where a request would go, what would change the route,
why a decision was made, or what is waiting for you. It can also submit a request, once you have
seen the route and said yes.

It runs on **Salesforce Hosted MCP Servers**. Salesforce hosts the connection and the login, so
there is no server to run. Claude signs in as you, so it sees and does only what you can in
Salesforce.

**What it never does.** Claude cannot approve, reject, recall or reassign anything; approvers decide
in Salesforce. It cannot change a record or a rule. The matrix decides every route, and every
figure, rule and approver Claude gives you comes from the matrix's own answer.

## Contents

1. [The two connectors](#1-the-two-connectors)
2. [Setting it up (administrators, once per org)](#2-setting-it-up-administrators-once-per-org)
3. [Connecting Claude (each person, once)](#3-connecting-claude-each-person-once)
4. [Things to ask](#4-things-to-ask)
5. [How a submission stays safe](#5-how-a-submission-stays-safe)
6. [Troubleshooting](#6-troubleshooting)
7. [For maintainers](#7-for-maintainers)

---

## 1. The two connectors

| Connector | For | URL in `amf-dev` |
|---|---|---|
| **Approval Matrix** | everyone who submits or approves | `https://api.salesforce.com/platform/mcp/v1/custom/AMFApprovalMatrix` |
| **Approval Matrix Admin** | the matrix's administrators | `https://api.salesforce.com/platform/mcp/v1/custom/AMFApprovalMatrixAdmin` |

**Approval Matrix** has eight tools:

| Tool | Asks first? | What it does |
|---|---|---|
| `find_record` | no | Finds a Purchase Request or Opportunity by number, name or Id |
| `preview_route` | no | Where a record would go, which rule decides it, and the values it read. Submits nothing |
| `what_if_route` | no | Where it would go with different values, against today. Changes nothing |
| `submit_for_approval` | **yes** | Submits a record you have just previewed, by the route you confirmed |
| `get_decision_facts` | no | The recorded facts behind a decision already made, for Claude to explain |
| `get_briefing_facts` | no | For the approver an approval is waiting on: the facts to decide with. Never a recommendation |
| `list_my_requests` | no | Where your own requests of the last 90 days stand |
| `list_my_approvals` | no | What is waiting for your approval |

**Approval Matrix Admin** has four, all read-only:

| Tool | What it does |
|---|---|
| `get_matrix_context` | The grammar, and an object's fields, picklist values, active rules and approval processes |
| `check_rule_draft` | Runs every release check on a rule Claude drafted, and returns the file to commit only if it passes |
| `check_change_impact` | What a new, changed or removed rule would do to the last 90 days' records |
| `get_health_facts` | How the matrix has been doing: outcomes, each rule's share, rules that routed nothing, pending approvals |

Every tool takes a record the way people name it, such as "PR-00000047", a request name or an
opportunity name. If several records match, Claude shows them and asks which one you mean. Every
answer links to the record in Salesforce.

---

## 2. Setting it up (administrators, once per org)

### 2.1 In `amf-dev`

From the project root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup-claude-connector.ps1 -Admin
```

The script:
1. deploys the `mcp` package directory: the tool classes, `AMF_Mcp_Settings__c` and the two
   connector permission sets;
2. deploys the External Client App, `AMFClaudeConnector`, from `org-config/amf-dev`;
3. deploys the two MCP servers at Metadata API 67.0 (section 7.2 explains why);
4. activates both servers;
5. seeds the preview key (`scripts/setup-mcp.apex`), keeping one that already exists;
6. assigns `AMF_Claude_Connector_User`, or with `-Admin` `AMF_Claude_Connector_Admin`, to the
   CLI user, or to the users named by `-AssignTo`;
7. prints both URLs, the OAuth client ID, and the steps in section 3.

**A new External Client App can take up to 30 minutes** before its first login works. Run the
script again at any time: it skips what is already done.

### 2.2 Giving people access

The connector's login admits only holders of a connector permission set.

| Person | Assign |
|---|---|
| Submitter or approver | `Approval_Matrix_User` and `AMF_Claude_Connector_User` |
| Administrator | `Approval_Matrix_Admin` and `AMF_Claude_Connector_Admin` |

For example:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup-claude-connector.ps1 -SkipDeploy -AssignTo amfu1@amf.00daj000012gj9b.dev
```

No Agentforce or Einstein licence is needed. Claude writes the explanations, briefings and summaries
itself, from facts Apex returns. The person's profile needs API access, which Standard Platform User
and System Administrator have.

### 2.3 In another org

1. Deploy `force-app` and `mcp`:
   `sf project deploy start --source-dir force-app --source-dir mcp -o <alias>`, with that org's
   `AMF_USERNAME_DOMAIN`.
2. Give the org its own External Client App, in `org-config/<org>`: a copy of
   `org-config/amf-dev`'s four `AMFClaudeConnector` files. The consumer key is generated by the
   org and never kept in source.
3. Run the script with `-TargetOrg <alias> -OrgConfig <org>`.

A sandbox or scratch org's URLs have `/sandbox/` after `/v1/`; the script works that out. Hosted MCP
servers need Enterprise Edition or above, or Developer Edition.

---

## 3. Connecting Claude (each person, once)

You need the URL and the OAuth client ID that the setup script prints. In `amf-dev`, the client ID
is the External Client App's consumer key (Setup, External Client App Manager, Approval Matrix
Claude Connector, Settings, OAuth Settings).

**Before you connect,** log out of every other Salesforce org in your browser, and stay logged in to
this one. The login opens in that browser.

### 3.1 claude.ai, Claude Desktop and mobile

A connector added in claude.ai also appears in Claude Desktop and the mobile apps.

1. **Customize**, then **Connectors**, then **+**, then **Add custom connector**.
2. Name: `Approval Matrix`. URL: the first URL in section 1.
3. **Advanced settings**, then **OAuth Client ID**: the client ID. Leave **OAuth Client Secret**
   empty.
4. **Add**, then **Connect**. Log in to Salesforce and choose **Allow**.
5. In the connector's tool permissions, keep `submit_for_approval` on **Needs approval**. The other
   tools only read, so **Always allow** saves a prompt for each question.

Administrators add **Approval Matrix Admin** the same way, with the second URL.

### 3.2 Claude Code

```bash
claude mcp add --transport http --scope user approval-matrix https://api.salesforce.com/platform/mcp/v1/custom/AMFApprovalMatrix --client-id <client ID> --callback-port 38000
claude mcp add --transport http --scope user approval-matrix-admin https://api.salesforce.com/platform/mcp/v1/custom/AMFApprovalMatrixAdmin --client-id <client ID> --callback-port 38000
```

Then run `/mcp` in Claude Code, choose `approval-matrix`, and **Authenticate**. `claude mcp list`
shows it as connected. Port 38000 must stay as it is: it is the callback the External Client App
registers.

---

## 4. Things to ask

**Submitters**
- "Where would PR-00000047 go for approval?"
- "What if it were 120,000 and in APAC?"
- "Which rule decides the Dell laptops request, and why?"
- "Submit PR-00000047." Claude previews it, tells you the route, and submits only when you say yes.
- "Where do my requests stand?" / "Has PR-00000050 been approved yet?"

**Approvers**
- "What is waiting for my approval?"
- "Brief me on PR-00000050." Claude describes what is asked, why it was routed to you, the values
  and the steps so far. It never says whether to approve or reject.
- "Why did PR-00000042 go to the credit-risk queue?"

**Administrators** (Approval Matrix Admin)
- "Draft a rule for purchase requests: anything over 500,000 in EMEA should go to the finance
  committee." Claude reads the matrix's context, drafts the rule, and has every release check run
  on it before showing it. You get the Custom Metadata file to commit.
- "What would that rule change for recent requests?"
- "How has the matrix been doing over the last 90 days?"
- "Is any active rule routing nothing?"

**With your other connectors** (if you have them in Claude)
- "Check our approval matrix against the approval policy in my Google Drive." Claude reads the
  policy, previews and what-ifs test cases at its thresholds, and lists any disagreement.
- "What is waiting for my approval? Block an hour tomorrow morning to review it."

A rule Claude drafts routes nothing until you release it like any other rule change: save the file
in `force-app`, run the source gate, deploy, and run `scripts/validate-config.apex`.

---

## 5. How a submission stays safe

Three checks stand between Claude and a submission, and all of them hold even if Claude made a
mistake:

1. **You confirm.** `submit_for_approval` is marked as a tool that asks first. Its request names
   the record and the process, so what you approve is exactly what you saw.
2. **Salesforce checks that you previewed it.** Every `preview_route` answer carries a token
   signed in Apex with a key Claude never sees. The token is good for 15 minutes, for you, that
   record and that process only. A submission without a matching token is refused and writes nothing.
3. **The matrix decides again.** If the record or the matrix has changed since the preview, so that
   it would now go somewhere else, nothing is submitted. Claude tells you the new route and asks
   again.

The submission itself takes the same path as the Flow action, REST and the Agentforce assistant,
and writes the same decision log row.

---

## 6. Troubleshooting

| What you see | Why, and what to do |
|---|---|
| `invalid_client` at login | The External Client App is still propagating; wait up to 30 minutes. Or the OAuth Client ID is not the consumer key |
| `redirect_uri_mismatch` | Still propagating, or the client's callback is not registered. Claude Code must use `--callback-port 38000` |
| "Authorization with the MCP server failed" after a successful login | Check that the server is active (rerun the setup script). If it persists in claude.ai, try Claude Code, which connects directly |
| "user is not admin approved to access this app" | The person has no connector permission set (section 2.2) |
| A tool answers "Submitting through Claude is not set up in this org yet" | The preview key is missing; run `sf apex run --file scripts/setup-mcp.apex -o <alias>` |
| A submission is refused as "does not come from a preview" | Normal if the preview was of another record or route. Ask Claude to preview again |
| A submission is refused as "more than 15 minutes old" | Preview again, then confirm |
| Claude asks for approval before every read tool | Set the read tools to **Always allow** in the connector's settings |
| Another Salesforce org's login page opens | Log out of the other org first: the login uses your browser's current Salesforce session |

---

## 7. For maintainers

### 7.1 Where things live

| What | Where |
|---|---|
| The tools: `AMF_McpFindRecord`, `AMF_McpPreviewRoute`, `AMF_McpWhatIfRoute`, `AMF_McpSubmitRoute`, `AMF_McpDecisionFacts`, `AMF_McpBriefingFacts`, `AMF_McpMyRequests`, `AMF_McpMyApprovals`, `AMF_McpRuleContext`, `AMF_McpCheckRuleDraft`, `AMF_McpCheckImpact`, `AMF_McpHealthFacts` | `mcp/main/default/classes` |
| Shared: `AMF_McpSupport` (references, links, the token), `AMF_McpFactsOnly` (Claude in Einstein's place) | the same |
| The servers and their tool descriptions | `mcp/main/default/mcpServerDefinitions` |
| The preview key's setting, `AMF_Mcp_Settings__c` | `mcp/main/default/objects` |
| The permission sets | `mcp/main/default/permissionsets` |
| The External Client App and its OAuth policy | `org-config/amf-dev/main/default/externalClientApps`, `extlClntApp*` |
| Setup, key and probe scripts | `scripts/setup-claude-connector.ps1`, `scripts/setup-mcp.apex`, `scripts/mcp-probe.mjs` |

Each tool is a thin `global` invocable over an existing action or service. The matrix's logic stays
in the engine and in M13 to M15's classes, which M16 did not change.

### 7.2 Two platform rules

- **Everything in a tool class is `global`:** the class, its `@InvocableMethod`, its request and
  result classes, and their fields. A `public` invocable is not offered as a tool, and a `public`
  member breaks the tool's schema in Setup.
- **The server definitions deploy at Metadata API 67.0.** A tool's `readOnly`, `destructive`,
  `idempotent` and `openWorld` annotations exist only from 67.0. A deploy at this project's
  `sourceApiVersion`, 66.0, resets them all to false: every read tool would then make Claude ask
  first, and the submit tool would lose its warning. So `.forceignore` keeps the definitions out of
  every project deploy, and the setup script deploys them from a throwaway project at 67.0. The
  Apex stays at 62.0.

### 7.3 Adding or changing a tool

1. Write the `global with sharing` facade in `mcp/main/default/classes`, with its test over
   in-memory rules.
2. Add it to the server's definition, with a `descriptionOverride` of at most 1,024 characters.
   Write the description as a lookup: say what Claude does not know that only the tool does, what
   the tool is not for, and what to give the user (the M15 lesson). Set its four annotations.
3. Grant the class in the right connector permission set.
4. Run the setup script. A connected client sees the new tool on its next connection.

### 7.4 Checking it without a chat client

`scripts/mcp-probe.mjs` talks to a server the way an MCP client does:

```powershell
& 'C:\Program Files\sf\client\bin\node.exe' scripts/mcp-probe.mjs --server https://api.salesforce.com/platform/mcp/v1/custom/AMFApprovalMatrix --instance https://orgfarm-e5ccbd7218-dev-ed.develop.my.salesforce.com --client-id <client ID> --tool preview_route --args '{\"record\":\"PR-00000047\"}'
```

The first run opens the browser once to log in. It keeps the refresh token in `.mcp-probe/`, which
git ignores. It lists the tools with their annotations, lists the prompts, and calls a tool.
Arguments for an Apex tool go in an `inputs` array; the probe wraps the one input it is given.

The same Apex can be called without MCP through the REST Actions API, as the CLI user:
`POST /services/data/v66.0/actions/custom/apex/AMF_McpPreviewRoute` with
`{"inputs":[{"record":"PR-00000047"}]}`.
