# OneHub Self-Healing Agent — Build Runbook

## Salesforce → GitHub Actions → Claude API Integration

**Version:** 1.0  
**Last Updated:** April 2026  
**Author:** BCB Platform Architecture  
**Status:** Technical Specification

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Component Specifications](#component-specifications)
   - [GitHub Configuration](#github-configuration)
   - [Salesforce Configuration](#salesforce-configuration)
   - [GitHub Actions Workflow](#github-actions-workflow)
5. [Data Contracts](#data-contracts)
6. [Build Sequence](#build-sequence)
7. [Testing Checklist](#testing-checklist)
8. [Security Considerations](#security-considerations)

---

## Overview

### Purpose

This document specifies the build steps for an automated self-healing pipeline that:

1. Receives incident analyses from Salesforce Agentforce
2. Automatically generates code fixes using the Claude API
3. Raises Pull Requests for human review
4. Updates Salesforce with the outcome

### Automation Principle

The entire flow is automated. The **only human intervention** is reviewing and merging the Pull Request.

### Key Constraint

Claude Code CLI cannot run in GitHub Actions (it's a local VS Code tool). This solution uses the **Claude API** directly via HTTP calls instead.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  SALESFORCE                                                                 │
│                                                                             │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────────────────────┐  │
│  │ rflib_Log   │ ───▶ │ Record-     │ ───▶ │ Apex Service                │  │
│  │ AI_Fix_     │      │ Triggered   │      │ (HTTP POST to GitHub)       │  │
│  │ Status =    │      │ Flow        │      │                             │  │
│  │ Send for Fix│      └─────────────┘      └─────────────────────────────┘  │
│  └─────────────┘                                        │                   │
└─────────────────────────────────────────────────────────│───────────────────┘
                                                          │
                                                          │ repository_dispatch
                                                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  GITHUB ACTIONS WORKFLOW                                                    │
│                                                                             │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐  │
│  │ Checkout │ → │ Parse    │ → │ Read     │ → │ Call     │ → │ Write    │  │
│  │ Repo     │   │ Payload  │   │ Apex     │   │ Claude   │   │ Fixed    │  │
│  │          │   │          │   │ File     │   │ API      │   │ Code     │  │
│  └──────────┘   └──────────┘   └──────────┘   └──────────┘   └──────────┘  │
│                                                                             │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐                  │
│  │ Create   │ → │ Commit   │ → │ Create   │ → │ Update   │                  │
│  │ Branch   │   │ & Push   │   │ PR       │   │ SF       │                  │
│  └──────────┘   └──────────┘   └──────────┘   └──────────┘                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                                          │
                                                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PULL REQUEST                                                               │
│  Awaits human review and merge                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### Accounts & Access Required

| System | Access Needed |
|--------|---------------|
| Salesforce | System Administrator or permissions to deploy Apex, create Custom Metadata, create Flows |
| GitHub | Admin access to target repository (for secrets and workflow files) |
| Anthropic | Account with API access |

### API Keys to Obtain

| Key | Source | Purpose |
|-----|--------|---------|
| GitHub Personal Access Token | GitHub Developer Settings | Salesforce triggers workflow |
| Anthropic API Key | console.anthropic.com | GitHub Actions calls Claude |
| Salesforce Access Token | SFDX CLI or Connected App | GitHub Actions updates Salesforce |

---

## Component Specifications

---

### GitHub Configuration

#### 1. Personal Access Token (PAT)

**Location:** GitHub → Settings → Developer Settings → Personal Access Tokens → Fine-grained tokens

**Specification:**

| Setting | Requirement |
|---------|-------------|
| Name | Descriptive name for audit purposes |
| Expiration | Per security policy (recommend 90 days) |
| Repository Access | Restrict to target repository only |
| Permission: Actions | Read and write |
| Permission: Contents | Read and write |
| Permission: Pull Requests | Read and write |
| Permission: Metadata | Read |

**Output:** Token string to be stored in Salesforce Custom Metadata

---

#### 2. Repository Secrets

**Location:** GitHub → Repository → Settings → Secrets and variables → Actions

**Secrets to Create:**

| Secret Name | Contents | Purpose |
|-------------|----------|---------|
| `ANTHROPIC_API_KEY` | Anthropic API key | Authenticate to Claude API |
| `SF_INSTANCE_URL` | Salesforce org base URL | Callback to update record status |
| `SF_ACCESS_TOKEN` | Salesforce session/access token | Authenticate to Salesforce API |

---

#### 3. Workflow File

**Location:** `.github/workflows/ai-fix.yml`

**Trigger:** `repository_dispatch` with event type `ai-fix-request`

**Specification:** See [GitHub Actions Workflow](#github-actions-workflow) section below.

---

### Salesforce Configuration

#### 1. Custom Metadata Type: GitHub AI Fix Config

**Purpose:** Store GitHub connection details securely.

**Object Specification:**

| Property | Value |
|----------|-------|
| Label | GitHub AI Fix Config |
| API Name | `GitHub_AI_Fix_Config__mdt` |

**Field Specifications:**

| Field Label | API Name | Type | Length | Purpose |
|-------------|----------|------|--------|---------|
| GitHub Token | `GitHub_Token__c` | Text | 255 | PAT for GitHub API authentication |
| Repository Owner | `Repository_Owner__c` | Text | 100 | GitHub username or org (e.g., `McForce`) |
| Repository Name | `Repository_Name__c` | Text | 100 | Repository name (e.g., `SB-POC`) |
| Enabled | `Enabled__c` | Checkbox | — | Kill switch for the integration |

**Record to Create:**

| Field | Value |
|-------|-------|
| Label | Production |
| DeveloperName | Production |
| All config fields | Populated with actual values |

---

#### 2. Remote Site Setting

**Purpose:** Allow Apex HTTP callouts to GitHub API.

**Specification:**

| Property | Value |
|----------|-------|
| Name | GitHub_API |
| URL | `https://api.github.com` |
| Active | Yes |

---

#### 3. Custom Field: AI Fix Status

**Object:** `rflib_Logs__c`

**Field Specification:**

| Property | Value |
|----------|-------|
| Label | AI Fix Status |
| API Name | `AI_Fix_Status__c` |
| Type | Picklist |

**Picklist Values:**

| Value | Meaning |
|-------|---------|
| Pending | Default state, not yet reviewed |
| Send for Fix | Triggers the automation |
| Processing | GitHub Action is running |
| PR Raised | Fix complete, awaiting review |
| Fix Failed | Automation encountered an error |

---

#### 4. Apex Service Class

**Name:** `GitHubAIFixService`

**Purpose:** Invocable Apex class that triggers the GitHub Actions workflow.

**Functional Specification:**

The class must:

1. **Be invocable from Flow** using `@InvocableMethod` annotation
2. **Accept a Record ID** as input parameter
3. **Read configuration** from `GitHub_AI_Fix_Config__mdt`
4. **Validate** the configuration is enabled
5. **Query the rflib_Logs__c record** to get:
   - Record ID
   - Record Name
   - Created Date
   - Log Level
   - Context
   - Apex Code Root Cause Determination
6. **Validate** the Root Cause Determination field is populated
7. **Construct JSON payload** containing all incident details
8. **Make HTTP POST** to GitHub repository dispatch endpoint:
   - Endpoint: `https://api.github.com/repos/{owner}/{repo}/dispatches`
   - Method: POST
   - Headers: Authorization (Bearer token), Accept, Content-Type, API Version
   - Body: event_type + client_payload with incident data
9. **Handle response codes:**
   - 204: Success → update record status to "Processing"
   - 404: Repository not found → return error
   - 401: Authentication failed → return error
   - Other: Return error with details
10. **Return response** to Flow with success/failure status and message

**Test Class Specification:**

The test class must:

1. Create test rflib_Logs__c records
2. Mock HTTP callouts with various response codes
3. Test success scenario
4. Test missing Root Cause scenario
5. Test GitHub error scenarios
6. Achieve required code coverage

---

#### 5. Record-Triggered Flow

**Name:** AI Fix Trigger - rflib_Logs

**Purpose:** Automatically invoke the Apex service when status changes.

**Trigger Specification:**

| Property | Value |
|----------|-------|
| Object | `rflib_Logs__c` |
| Trigger | Record is updated |
| Condition | `AI_Fix_Status__c` equals `Send for Fix` |
| When to Run | Only when record is updated to meet condition |
| Optimization | Actions and Related Records |

**Action Specification:**

| Property | Value |
|----------|-------|
| Action Type | Apex Action |
| Apex Class | `GitHubAIFixService` |
| Input Parameter | Record ID from trigger record |

---

### GitHub Actions Workflow

**Filename:** `.github/workflows/ai-fix.yml`

**Trigger:** `repository_dispatch` event with type `ai-fix-request`

---

#### Workflow Steps Specification

**Step 1: Log Incident Received**

- Purpose: Audit trail and debugging
- Action: Echo incident ID, name, timestamp to workflow log

---

**Step 2: Checkout Repository**

- Purpose: Get repository code into the runner
- Action: Use `actions/checkout@v4`
- Configuration: Full history (`fetch-depth: 0`), use GITHUB_TOKEN

---

**Step 3: Setup Node.js**

- Purpose: Required for any Node-based tooling
- Action: Use `actions/setup-node@v4`
- Configuration: Node.js version 20

---

**Step 4: Configure Git**

- Purpose: Allow commits from the workflow
- Action: Set git user.name and user.email for the AI agent

---

**Step 5: Parse Incident Payload**

- Purpose: Extract structured data from the dispatch payload
- Action: Parse the `client_payload` to extract:
  - Incident ID
  - Incident Name
  - Root Cause Determination
- Output: Store in environment variables or files for subsequent steps

---

**Step 6: Extract Class Information from Root Cause**

- Purpose: Determine which Apex file to modify
- Action: Parse the Root Cause Determination to extract:
  - Apex class name
  - Method name (if present)
  - Line number (if present)
- Logic: Use grep/sed/awk or a script to find patterns like "Class: ClassName" or "ClassName.methodName"
- Output: Class name stored in variable

---

**Step 7: Read Current Apex File**

- Purpose: Get the current code to send to Claude
- Action: Read file from `force-app/main/default/classes/{ClassName}.cls`
- Validation: Check file exists; fail gracefully if not found
- Output: File contents stored in variable or temp file

---

**Step 8: Call Claude API**

- Purpose: Generate the fixed code
- Action: HTTP POST to `https://api.anthropic.com/v1/messages`
- Authentication: Use `ANTHROPIC_API_KEY` secret in header
- Request Body:
  - Model: `claude-sonnet-4-20250514` (or appropriate model)
  - Max tokens: Sufficient for full class response (e.g., 8192)
  - Messages: Single user message containing:
    - The current Apex code (full file)
    - The Root Cause Determination
    - Clear instruction to return ONLY the complete fixed code
- Response Handling:
  - Parse JSON response
  - Extract the text content (the fixed code)
  - Handle errors (rate limits, invalid responses)
- Output: Fixed code stored in variable or temp file

---

**Step 9: Write Fixed Code to File**

- Purpose: Apply the fix to the repository
- Action: Write the Claude response to the Apex file
- Validation: Ensure the response looks like valid Apex (basic sanity check)

---

**Step 10: Create Branch**

- Purpose: Isolate changes per governance rules
- Action: `git checkout -b ai-fix/{incident-id}`
- Naming: Branch name must include incident ID for traceability

---

**Step 11: Commit Changes**

- Purpose: Record the fix with proper attribution
- Action: `git add` the modified file, `git commit` with structured message
- Commit Message Format:
  ```
  fix(ClassName): brief description
  
  Correlation-ID: {incident-id}
  Root-Cause: {one-line summary}
  Generated-By: Claude API via GitHub Actions
  ```

---

**Step 12: Push Branch**

- Purpose: Make branch available for PR
- Action: `git push origin ai-fix/{incident-id}`

---

**Step 13: Create Pull Request**

- Purpose: Submit fix for human review
- Action: Use GitHub CLI (`gh pr create`) or GitHub API
- PR Title: `AI Fix: {ClassName} - {brief description}`
- PR Body Must Include:
  - Incident reference (ID, name)
  - Summary of the Root Cause Determination
  - Description of fix applied
  - Note that this was auto-generated
  - Reminder that human review is required

---

**Step 14: Update Salesforce - Success**

- Purpose: Close the loop, update incident status
- Condition: Previous steps succeeded
- Action: HTTP PATCH to Salesforce REST API
  - Endpoint: `{SF_INSTANCE_URL}/services/data/v59.0/sobjects/rflib_Logs__c/{incident-id}`
  - Body: `{"AI_Fix_Status__c": "PR Raised"}`
  - Authentication: Bearer token using `SF_ACCESS_TOKEN`

---

**Step 15: Update Salesforce - Failure**

- Purpose: Record failure for investigation
- Condition: Any previous step failed
- Action: HTTP PATCH to Salesforce REST API
  - Body: `{"AI_Fix_Status__c": "Fix Failed"}`

---

**Step 16: Upload Logs as Artifact**

- Purpose: Debugging and audit trail
- Condition: Always (success or failure)
- Action: Use `actions/upload-artifact@v4`
- Content: Workflow logs, Claude API response
- Retention: 30 days

---

## Data Contracts

### Salesforce → GitHub Dispatch Payload

The Apex service sends this structure to GitHub:

```json
{
  "event_type": "ai-fix-request",
  "client_payload": {
    "incidentId": "a]8Qy000000XXXXX",
    "incidentName": "LOG-000123",
    "timestamp": "2026-04-16T10:30:00.000Z",
    "logLevel": "ERROR",
    "context": "Mall_Ping_AuthProviderCustomPlugin.handleCallback",
    "rootCauseDetermination": "Full text of the Apex Code Root Cause Determination field..."
  }
}
```

### Root Cause Determination Requirements

For the workflow to parse correctly, the Agentforce Root Cause Determination **must** include:

| Information | Example Format | Purpose |
|-------------|----------------|---------|
| Class Name | `Class: Mall_Ping_AuthProviderCustomPlugin` or clearly stated | Identifies which file to modify |
| Method Name | `Method: handleCallback` | Context for the fix |
| Line Number | `Line: 47` | Precise location |
| Error Type | `Error: NullPointerException` | Understanding the issue |
| Root Cause | Explanation of why the error occurs | Context for Claude |
| Recommended Fix | What should be changed | Direction for Claude |

### Claude API Request

```json
{
  "model": "claude-sonnet-4-20250514",
  "max_tokens": 8192,
  "messages": [
    {
      "role": "user",
      "content": "Here is an Apex class that needs fixing:\n\n```apex\n{CURRENT_CODE}\n```\n\nRoot Cause Determination:\n{ROOT_CAUSE}\n\nInstructions:\n1. Fix the issue described in the Root Cause Determination\n2. Follow Apex best practices (null safety, bulkification, proper error handling)\n3. Add a brief comment explaining the fix\n4. Return ONLY the complete fixed Apex class code, no explanations"
    }
  ]
}
```

### Claude API Response (Expected)

```json
{
  "content": [
    {
      "type": "text",
      "text": "public class Mall_Ping_AuthProviderCustomPlugin { ... fixed code ... }"
    }
  ]
}
```

---

## Build Sequence

### Phase 1: GitHub Setup

| Step | Task | Validation |
|------|------|------------|
| 1.1 | Create Personal Access Token | Token generated and copied |
| 1.2 | Create repository secret: ANTHROPIC_API_KEY | Secret saved |
| 1.3 | Create repository secret: SF_INSTANCE_URL | Secret saved |
| 1.4 | Create repository secret: SF_ACCESS_TOKEN | Secret saved |
| 1.5 | Create workflow file in repo | File committed to main branch |

### Phase 2: Salesforce Configuration

| Step | Task | Validation |
|------|------|------------|
| 2.1 | Create Custom Metadata Type | Type visible in Setup |
| 2.2 | Add fields to Custom Metadata Type | All 4 fields created |
| 2.3 | Create Custom Metadata record | Record saved with config values |
| 2.4 | Create Remote Site Setting | GitHub_API active |
| 2.5 | Create AI_Fix_Status__c field (if not exists) | Field on rflib_Logs__c |

### Phase 3: Apex Development

| Step | Task | Validation |
|------|------|------------|
| 3.1 | Develop GitHubAIFixService class | Compiles without errors |
| 3.2 | Develop test class | Compiles without errors |
| 3.3 | Deploy to Salesforce | Deployment succeeds |
| 3.4 | Run tests | All tests pass, coverage met |

### Phase 4: Flow Creation

| Step | Task | Validation |
|------|------|------------|
| 4.1 | Create Record-Triggered Flow | Flow saved |
| 4.2 | Configure trigger conditions | Conditions set correctly |
| 4.3 | Add Apex action | Action configured with input |
| 4.4 | Activate Flow | Flow shows as Active |

### Phase 5: Integration Testing

| Step | Task | Validation |
|------|------|------------|
| 5.1 | Create test rflib_Logs__c record | Record created with Root Cause |
| 5.2 | Change status to 'Send for Fix' | Flow triggers |
| 5.3 | Verify GitHub Action runs | Workflow visible in Actions tab |
| 5.4 | Verify Claude API called | Logs show API response |
| 5.5 | Verify PR created | PR visible in repository |
| 5.6 | Verify Salesforce updated | Status shows 'PR Raised' |

---

## Testing Checklist

### Unit Tests

| Test | Expected Result |
|------|-----------------|
| Apex service with valid record | Returns success, calls GitHub |
| Apex service with missing Root Cause | Returns error, no callout |
| Apex service with disabled config | Returns error, no callout |
| Apex service with GitHub 404 | Returns appropriate error |
| Apex service with GitHub 401 | Returns appropriate error |

### Integration Tests

| Test | Expected Result |
|------|-----------------|
| Manual GitHub dispatch (via CLI/API) | Workflow runs successfully |
| Workflow with missing Apex file | Fails gracefully, updates SF |
| Workflow with Claude API error | Fails gracefully, updates SF |
| Workflow with invalid SF token | PR created, SF update fails (logged) |
| Full end-to-end | PR created, SF updated |

### Edge Cases

| Scenario | Expected Handling |
|----------|-------------------|
| Very large Apex class (>10KB) | Claude handles within token limit |
| Root Cause doesn't specify class | Workflow fails with clear error |
| Class name has special characters | Properly escaped in file path |
| Concurrent incidents for same class | Separate branches, separate PRs |
| PR branch already exists | Workflow fails or overwrites (document behavior) |

---

## Security Considerations

### Secret Management

| Secret | Storage Location | Access Control |
|--------|------------------|----------------|
| GitHub PAT | Salesforce Custom Metadata | Encrypted at rest, admin-only access |
| Anthropic API Key | GitHub Secrets | Encrypted, only available to workflows |
| SF Access Token | GitHub Secrets | Encrypted, only available to workflows |

### Token Rotation

| Token | Recommended Rotation | Process |
|-------|---------------------|---------|
| GitHub PAT | 90 days | Regenerate, update Custom Metadata |
| Anthropic API Key | As needed | Regenerate, update GitHub Secret |
| SF Access Token | Session-based | For production: implement refresh token flow |

### Audit Trail

| Event | Where Logged |
|-------|--------------|
| Flow execution | Salesforce Flow Run History |
| Apex callout | Salesforce Debug Logs |
| Workflow execution | GitHub Actions logs |
| Claude API call | GitHub Actions logs (response logged) |
| Git operations | Git history |
| PR creation | GitHub PR history |

### Governance Boundaries

| Rule | Enforcement |
|------|-------------|
| AI cannot commit to main | Workflow creates feature branch only |
| AI cannot merge PRs | No merge permissions in workflow |
| AI cannot deploy code | No deployment steps in workflow |
| Human review required | Branch protection rules on main |

---

## Appendix: File Locations

| File | Repository Path |
|------|-----------------|
| Workflow | `.github/workflows/ai-fix.yml` |
| Apex Service | `force-app/main/default/classes/GitHubAIFixService.cls` |
| Apex Test | `force-app/main/default/classes/GitHubAIFixServiceTest.cls` |
| Agent Instructions | `CLAUDE.md` (repo root) |
| This Runbook | `docs/AI_FIX_AGENT_RUNBOOK.md` |