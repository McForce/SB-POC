# OneHub POC Dependencies

This package contains the dependencies required for the `OSB_SN_UserSubscription_CTRL` class to deploy successfully.

## Contents

### 1. Subscribed_Solutions__c Custom Object

A custom object that stores user subscription and notification preferences.

| Field | Type | Description |
|-------|------|-------------|
| `Solution_Name__c` | Text(255) | The name of the subscribed solution |
| `Notification_Enabled__c` | Checkbox | Master notification toggle |
| `Email_Alerts__c` | Checkbox | Email alert preference |
| `Push_Notifications__c` | Checkbox | Push notification preference |
| `Frequency__c` | Long Text Area | JSON-formatted frequency settings |
| `Last_Modified_Date__c` | DateTime | Last modification timestamp |

### 2. RFLIB Stub Classes

Minimal stub implementations of the RFLIB logging framework:
- `RFLIB_Logger.cls` - Logger class with info/debug/warn/error/fatal methods
- `RFLIB_LoggerUtil.cls` - Factory class with `getLogger()` method

> **Note:** These are stub classes for POC/demo purposes only. For production, 
> install the full RFLIB package from [GitHub](https://github.com/j-fischer/rflib) 
> or AppExchange.

---

## Deployment Instructions

### Option 1: Deploy via SFDX CLI

```bash
# Navigate to the package directory
cd sfdx-dependencies

# Authenticate to your org (if not already)
sf org login web -a MyOrgAlias

# Deploy the metadata
sf project deploy start --source-dir force-app --target-org MyOrgAlias
```

### Option 2: Deploy via VS Code

1. Open this folder in VS Code with the Salesforce Extension Pack installed
2. Right-click on the `force-app` folder
3. Select **SFDX: Deploy Source to Org**

### Option 3: Deploy via Workbench

1. Create a ZIP of the `force-app/main/default` contents
2. Go to [Workbench](https://workbench.developerforce.com)
3. Navigate to **Migration** → **Deploy**
4. Upload the ZIP and deploy

---

## Deployment Order

Deploy this package **BEFORE** deploying:
- `OSB_SN_UserSubscription_CTRL.cls`
- Any other classes that reference `RFLIB_Logger` or `Subscribed_Solutions__c`

---

## Post-Deployment Verification

After deployment, verify:

1. **Custom Object exists:**
   ```
   Setup → Object Manager → Subscribed Solutions
   ```

2. **Fields are present:**
   - Solution_Name__c
   - Notification_Enabled__c
   - Email_Alerts__c
   - Push_Notifications__c
   - Frequency__c
   - Last_Modified_Date__c

3. **RFLIB classes compile:**
   ```
   Setup → Apex Classes → RFLIB_Logger, RFLIB_LoggerUtil
   ```

---

## Creating Test Data

For the POC demo, you may want to create test subscription records:

```apex
// Execute in Anonymous Apex
Subscribed_Solutions__c testPref = new Subscribed_Solutions__c(
    Solution_Name__c = 'API Marketplace',
    Notification_Enabled__c = true,
    Email_Alerts__c = true,
    Push_Notifications__c = false,
    Frequency__c = '{"type":"daily","time":"09:00"}',
    Last_Modified_Date__c = System.now()
);
insert testPref;
System.debug('Created test preference: ' + testPref.Id);
```

---

## Troubleshooting

### "Invalid type: RFLIB_Logger"
- Ensure `RFLIB_Logger.cls` and `RFLIB_LoggerUtil.cls` are deployed
- These must be deployed BEFORE classes that reference them

### "Invalid type: Subscribed_Solutions__c"
- Ensure the custom object and all fields are deployed
- Check Setup → Object Manager to verify the object exists

### "DML requires SObject or SObject list type"
- This occurs if the object doesn't exist in the org
- Deploy the custom object first, then retry

---

## Architecture Notes

The `OSB_SN_UserSubscription_CTRL` class:

1. **Reads** user preferences from `Subscribed_Solutions__c`
2. **Writes** updated preferences back to the same object
3. **Logs** all operations via `RFLIB_Logger`

The class expects at least one `Subscribed_Solutions__c` record per user. 
If no records exist for a user, the code throws `List index out of bounds: 0`.

This is the **intentional error scenario** used in the POC to demonstrate 
AI-driven root cause analysis.
