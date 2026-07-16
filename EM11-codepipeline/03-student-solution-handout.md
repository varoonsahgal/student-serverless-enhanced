# EM11 — The Pipeline That Wouldn't Deploy — Solution Handout

> Instructor answer key.

## Original Symptom

Pipeline: Source `Succeeded`, Deploy `Failed`. CodeBuild log shows `AccessDeniedException` on `lambda:UpdateFunctionCode`.

## Root Cause

The **CodeBuild service role** has permissions for CloudWatch Logs and S3 artifacts but **not** `lambda:UpdateFunctionCode`. The buildspec's `aws lambda update-function-code ...` command therefore fails with `AccessDeniedException`, failing the Deploy stage. The pipeline role is fine — the missing permission is on the build role.

## Exact Fix

Add `lambda:UpdateFunctionCode` (scoped to the target function ARN) to the CodeBuild service role.

### Console

1. CodeBuild → your project → **Build details** → click the **Service role**.
2. **Add permissions → Create inline policy** → JSON:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": "lambda:UpdateFunctionCode",
       "Resource": "arn:aws:lambda:<region>:<account>:function:<target-fn>"
     }]
   }
   ```
3. Save, then re-run the pipeline.

### CLI

```bash
ROLE=<codebuild service role name>
FN_ARN=<target lambda arn>
aws iam put-role-policy --role-name "$ROLE" --policy-name allow-deploy \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"lambda:UpdateFunctionCode\",\"Resource\":\"$FN_ARN\"}]}"

aws codepipeline start-pipeline-execution --name <pipeline>
```

> Permanent fix (solution Terraform): the CodeBuild role policy includes `lambda:UpdateFunctionCode` on the target function ARN.

## Validation Evidence

```bash
aws codepipeline start-pipeline-execution --name <pipeline>
# wait, then:
aws codepipeline get-pipeline-state --name <pipeline> \
  --query 'stageStates[].{stage:stageName,status:latestExecution.status}'
# both stages "Succeeded"

aws lambda get-function-configuration --function-name <target-fn> \
  --query LastModified   # timestamp is newer than before
```

## Common Mistakes

- **Adding the permission to the pipeline role** instead of the CodeBuild role — the pipeline didn't make the call.
- **Granting `lambda:*` on `*`** — works but over-broad; scope to the function.
- **Forgetting to re-run the pipeline** — IAM fixes don't retro-run the failed execution; start a new one.
- **Editing the Lambda by hand to "fix it"** — that defeats the CI/CD lesson; the pipeline must be able to deploy.

## Distinguish From Similar Failures

| Failing stage | Error | Diagnosis |
|---------------|-------|-----------|
| Deploy (CodeBuild) | `AccessDeniedException` on the API your buildspec calls | CodeBuild **service role** gap (**this lab**) |
| Source | S3 access denied / object missing | **Pipeline role** artifact permissions, or the source object isn't there |
| Deploy | `YAML_FILE_ERROR` / command not found | buildspec syntax or image problem, not IAM |
| Nothing runs at all | Pipeline trigger/source configuration | Check the source action settings |

## Key Takeaways / Exam Angle

- **CodeBuild's service role is the identity for every AWS call in a buildspec.** Deploy failures are usually its missing permissions.
- **Distinguish pipeline role vs. build role** — a frequent CI/CD exam distinction.
- **Re-run the pipeline** after IAM changes; scope permissions to specific resource ARNs.
