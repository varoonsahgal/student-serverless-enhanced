# EM11 — The Pipeline That Wouldn't Deploy: CI/CD — Student Handout

> **Region:** All lab resources are deployed in **US West (Oregon) — `us-west-2`**. Before running any AWS CLI command or opening the console, confirm your region is `us-west-2`. If you are in the wrong region, your resources will not exist and every command will fail.


## Lab Goals

- Read an **AWS CodePipeline** execution and find the failing stage.
- Diagnose a **CodeBuild** failure caused by a missing IAM permission.
- Re-run a pipeline after fixing it.

## Scenario

**Acme Retail** ships Lambda updates through a CodePipeline: an artifact lands in S3, CodeBuild deploys it. Right now every pipeline run **fails at the Deploy stage** — the code never reaches the function. The team is stuck making risky manual console edits because the pipeline is dead.

**Microcredential mapping:** this lab mirrors the CI/CD half of **Challenge 7** of the assessment (application updates must flow through CodePipeline, not unmanaged console edits).

## Architecture

```
S3 source.zip ─▶ CodePipeline ─▶ [Source] ─▶ [Deploy: CodeBuild]
                                                  │ aws lambda update-function-code
                                                  ▼
                                            target Lambda   (deploy fails)
```

## Starting Symptom

1. The pipeline shows the **Source** stage **Succeeded** and the **Deploy** stage **Failed**.
2. The CodeBuild build log ends with an **`AccessDeniedException`** on `lambda:UpdateFunctionCode`.
3. The target Lambda's code is never updated.

## Time Limit

**35 minutes.**

## Guided Investigation Hints

1. Open the failed pipeline execution → the **Deploy** action → **Details** → the **CodeBuild build log**. Read the last error.
2. `AccessDeniedException ... lambda:UpdateFunctionCode` means the **CodeBuild service role** (not the pipeline role) lacks permission to update the function.
3. CodeBuild runs your buildspec commands using its **service role**. Any AWS API the build calls must be allowed by that role.
4. After fixing IAM, re-run:
   ```bash
   aws codepipeline start-pipeline-execution --name <pipeline>
   ```

## Debugging Playbook (How a Pro Thinks)

Pipelines fail with *layers of indirection* — your job is to find the **identity that actually made the failing call**:

```
CodePipeline (pipeline role: moves artifacts between stages)
   └── Deploy stage → CodeBuild project (SERVICE ROLE: runs your buildspec commands)
            └── aws lambda update-function-code   ← this call uses the CodeBuild role
```

Rule: **whoever executes the command needs the permission.** Buildspec commands run as the CodeBuild service role, so that's where `lambda:UpdateFunctionCode` belongs — not on the pipeline role, and not on your own user.

Workflow discipline: after an IAM fix, failed executions don't retro-heal. Start a **new** execution (`aws codepipeline start-pipeline-execution`) and watch it stage by stage. And prove the deploy actually landed: check the target function's `LastModified` timestamp, not just the green checkmark.

## Things to Check

- **CodePipeline → your pipeline → the failed execution → Deploy → View logs.**
- **CodeBuild → your project → Build details → Service role:** what does its policy allow?
- The **exact action** named in the `AccessDeniedException`.
- **Lambda → target function → Last modified:** does it change after a successful run?

## Validation Criteria

You are done when:

1. A new pipeline execution shows **both stages Succeeded**.
2. The CodeBuild log shows `update-function-code` succeeded.
3. The target Lambda's **Last modified** timestamp updates (the deploy took effect).

## Key Takeaways

- **CodeBuild uses its *service role* to call AWS APIs from your buildspec.** Missing action = build fails with `AccessDeniedException`.
- **The pipeline role and the build role are different** — grant the permission to the one actually making the call.
- **Least privilege:** scope `lambda:UpdateFunctionCode` to the specific function ARN.

## Reflection Questions

1. Why did the Source stage succeed but Deploy fail?
2. How would you tell whether a permission belongs on the **pipeline** role vs. the **CodeBuild** role?
3. What extra stage would you add so a human approves before deploys reach production?
