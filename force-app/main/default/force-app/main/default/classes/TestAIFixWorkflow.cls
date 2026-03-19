/**
 * @description Temporary test class to trigger the GitHub Actions workflow.
 *              Delete this file after confirming the workflow runs.
 */
public with sharing class TestAIFixWorkflow {
    public static String ping() {
        return 'Workflow test';
    }
}
```

5. Scroll down to the **Commit changes** section
6. Set the commit message to: `Test: Trigger AI fix validation workflow`
7. This time select **Create a new branch for this commit and start a pull request**
8. In the branch name field, type: `ai-fix/test-workflow`
9. Click **Propose changes**

**Step 4 — Create the Pull Request**

GitHub will take you to the Pull Request creation screen.

1. Set the **Title** to: `[AI Fix] Test workflow validation`
2. In the description, paste:
```
## Test PR

This PR exists solely to trigger the `validate-ai-fix` GitHub Actions workflow
so the status check registers and becomes available in branch protection rules.

**This PR should be closed without merging after the workflow runs.**
