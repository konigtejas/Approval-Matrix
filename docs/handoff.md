# Handoff — what's next after M15

**As of 2026-10-23.** `develop` holds two more AI phases, each gated in `amf-dev` and committed:

- **M14, the assistant for submitters and approvers** (`74ea4ed`). The Approval Matrix Assistant
  gained four abilities:
  - a what-if ("where would this go if the amount were 120,000?"), answered by a new write-nothing
    engine entry, `previewWith()`;
  - "where are my requests?";
  - "what is waiting for my approval?";
  - a briefing for the approver an approval is waiting on.

  The current approver of a pending approval may now read why it was routed to them, in the briefing
  and on the timeline.
- **M15, the Approval Matrix Admin Assistant** (`11941dc`). A second agent, for administrators only.
  It changes nothing. It:
  - drafts a rule from a description, and shows it only once it passes the release checks;
  - checks what a change would do to recently decided requests, through a new write-nothing engine
    entry, `previewEach()`;
  - reports how the matrix has been doing, counted in Apex.

AI still never decides (architecture §1, principle 6). A draft routes nothing until an administrator
releases its file through source and the gate.

This is the short version. The sources are:

- `docs/technical-log.md`: the status board, M14 and M15, and M15.6's table of open items;
- `docs/decisions.md`: the choices, dated 2026-10-23;
- `docs/build-playbook.md`: Part 3's gates, including M14's step 9 and M15's step 11;
- `docs/architecture.md`: v3.0, the target design.

A fresh session reads `CLAUDE.md` first: it decides what is authorised. Nothing beyond M15 is.

**Deploying.** There are three package directories, as since M13. Set `AMF_USERNAME_DOMAIN` first:

```powershell
$env:AMF_USERNAME_DOMAIN = 'amf.00daj000012gj9b.dev'
sf project deploy start -o amf-dev
```

Three kinds of change need a step after the deploy:
- **An agent.** A deploy does not change the agent people talk to. Publish and activate it:

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-agent.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-agent.ps1 -AgentName AMF_Matrix_Admin_Assistant
  ```

  Every publish is a new, permanent version. The submitters' assistant is at v7 and the admin
  assistant at v1. Their suites are `AMF_Approval_Assistant_Tests` (14 cases, 42/42) and
  `AMF_Matrix_Admin_Assistant_Tests` (6 cases, 18/18). `sf agent test create` writes the definition
  into `force-app`; move it to `org-config/amf-dev`.
- **A prompt template.** New content makes a new version, which Einstein does not use until the source
  names it. Deploy, retrieve, and take the retrieved form, with `activeVersionIdentifier`, into
  source (technical log M13.7a, M15.3e). There are three templates now.
- **Agent instructions.** Say what the model does not know, name tools as lookups, and describe no
  answer the model could fill in by itself. Without that, the admin agent invented drafts and
  counts instead of calling its tools (technical log M15.3f). The local trace of any preview session,
  `.sfdx/agents/<agent>/sessions/<id>/traces/*.json`, shows whether an action ran: look for a
  `FunctionStep`.

---

## 1. Owed by the user — the manual UI checks

Three checks are owed, all in the browser, as the admin:

1. **M15, gate step 11.** In the Agentforce panel, choose **Approval Matrix Admin Assistant**:
   - draft a rule, for example "Purchase requests over 500,000 in EMEA go to the finance committee";
   - check its impact;
   - ask for a health report;
   - check that it refuses "deploy it".
2. **M14, gate step 9.** On a record, choose **Approval Matrix Assistant** and ask:
   - "Where would this go?"
   - "What if the amount were 120000?"
   - "Where do my requests stand?"
   - "What is waiting for my approval?"

   Then submit a throwaway Purchase Request, reassign its work item to yourself, ask "Brief me on
   it", and recall the throwaway.
3. **M13, gate step 11.** Open PR-00000042's newest timeline entry and use **Explain in plain
   English**.

The panel's page context and how it renders submit's confirmation are still unobserved (technical
log M13.7). Record the results in the technical log as M15.7.

### Also open

- **Access.** The assistants work for the admin user, who has every licence and permission set.
  Pallab Saikia, a System Administrator added on 2026-10-23, has none of them, by the user's choice.
  amf-dev has 5 Agentforce licences, 1 in use.
- **Grok Bot holds System Administrator**, for the UI suite. Return it to Standard User between runs.
- **The demo requests PR-00000045 to -48** serve both agents' tests. Demonstrate submission on a new
  record. The admin suite also expects nothing to be assigned to the CLI user.
- **Seven approvals are pending, left by earlier phases:** PR-00000002, -03, -05, -06, -07, -27 and
  -28. The impact check skips them.
- **PR-00000014 to -20 and -23 to -25** still carry *Matrix Submission* with no pending approval. They
  are M6 spike records, owned by the Flow phase's teardown.

---

## 2. Where the build stands: sixteen phases

| Phase | Delivered | Status |
|---|---|---|
| **M0–M3** | The MVP: guard, data model, evaluator, engine, Classic strategy, two templates, the submit action | Complete |
| **M4** | Configuration validator, source gate, post-deploy script | Complete |
| **M5** | Preview and the confirmation modal | Complete |
| **M6** | Flow approvals spike, research only | Complete; the unanimous value is still open |
| **M7** | Decision timeline LWC | Complete |
| **M8** | Guard integrity | Complete |
| **M9** | The full §4.1 grammar | Complete |
| **M10** | Flow invocable and REST entry points, per-record bulk submission | Complete |
| **M11** | Opportunity, a second governed object | Complete |
| **M12** | Template lifecycle, queue and committee templates, portability; M12.6 to M12.8 | Complete |
| **M13** | The Approval Matrix Assistant and plain-English explanations | Complete, bar its UI check |
| **M14** | What-if, my requests, my approvals, the approver's briefing; current approvers see why | Complete, bar its UI check |
| **M15** | The Approval Matrix Admin Assistant: draft a rule, check its impact, the matrix's health | Complete, bar its UI check |

At the end of M15: 404/404 Apex at 97% coverage, and 75/75 Jest.

---

## 3. What remains of the target design

### 3.1 Major functionality: Flow approvals, the second execution strategy

Unchanged since M13's handoff. The rest of architecture v3.0 is the Flow strategy:
- `Execution_Type__c`;
- `AMF_FlowApprovalStrategy`;
- Flow templates;
- a Flow history provider;
- the validator's Flow checks;
- a guard reset for cancelled submissions.

It is bound by `docs/spike-results.md` Round 2 and by engine classes staying at API ≤ 66. It is
partly blocked: unanimous approval on Flow group steps needs the `requiresMultiMemberApproval` value,
which a person must find in Flow Builder. The M6 teardown is part of it.

### 3.2 Smaller gaps, not phases

| Gap | Source |
|---|---|
| A drafted rule's name is checked against active rules only; widening `AMF_RuleProvider` would close it | M15, `docs/decisions.md` |
| The timeline LWC words a `Reassigned` row "X, for Y", without saying X is the new assignee | M14.3f |
| The submitters' assistant was not reworded after M15's finding; it passes its suite as it is | M15.6 |
| `AMF_AgentSubmitRoute` keeps its own approver-name lookup, duplicated by `AMF_AgentSupport.actorNamesOf()` | M14.6 |
| `messageOf` copies in two LWCs; `.prettierrc` indent | M7.6, M13.7 |
| `AMF_CmdtRuleProviderTest` pins the first shipped rule | M12.3b |
| DateTime fields, and Email, Phone, URL and Text Area fields, are refused | M9.5, playbook Part 5 |
| No translation (English literals); no timeline on phones | M7.6 |
| Rule descriptions are not snapshotted | `docs/decisions.md`, 2026-10-08 |
| The UI test suite has no M13, M14 or M15 case | M13.7 |
| `Lock_Decision_Log` still permits an unused stamp | M10.6 |
| husky would reformat whole files; commits run with `HUSKY=0` | M10.7 |

### 3.3 AI

M14 and M15 built all of the AI use cases proposed so far. Possible follow-ups, none of them
authorised:
- Lightning types for richer cards in the agent panel;
- the briefing as a card on the record page;
- Einstein's Trust Layer prompt-injection detection, an org setting that is still off.

### 3.4 Deliberately not planned

Approver resolution, chain objects, the Group Work Item pattern, the Approval Inbox and the SLA batch
were superseded at the v2.1 pivot. A template registry waits for §12 item 4's threshold. Recall from
the framework itself is out of scope; native recall works and clears the guard.

---

## Decisions waiting on the user

1. The three manual UI checks (section 1).
2. Whether to turn on the Trust Layer's prompt-injection and toxicity detection in `amf-dev`.
3. Whether Pallab Saikia, or any other user, should get access to the assistants.
4. The next phase, authorised in `CLAUDE.md`. For Flow approvals, say whether committee steps are
   wanted on Flow.
