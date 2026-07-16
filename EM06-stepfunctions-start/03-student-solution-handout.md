# EM06 — Orders Into the Void — Solution Handout

> Instructor answer key.

## Original Symptom

`POST /place-order` → `500`; no Step Functions executions; log shows `AccessDeniedException` on `states:StartExecution`.

## Root Cause

The placeorder Lambda's **execution role** has only basic Lambda logging permissions. It is missing `states:StartExecution` on the order-fulfillment state machine, so `sfn.start_execution(...)` fails with `AccessDeniedException` and the handler returns `500`. The `STATE_MACHINE_ARN` env var is correct — this is purely an IAM gap.

## Exact Fix

Add an inline (or managed) policy to the Lambda's role granting `states:StartExecution` on the specific state machine ARN.

### Console

1. Lambda → placeorder function → **Configuration → Permissions** → click the **execution role** (opens IAM).
2. **Add permissions → Create inline policy** → JSON:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": "states:StartExecution",
       "Resource": "arn:aws:states:<region>:<account>:stateMachine:<sm-name>"
     }]
   }
   ```
3. Save.

### CLI

```bash
ROLE=<placeorder role name>
SM_ARN=<state machine arn>

aws iam put-role-policy \
  --role-name "$ROLE" \
  --policy-name start-fulfillment \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"states:StartExecution\",\"Resource\":\"$SM_ARN\"}]}"
```

> Permanent fix (solution Terraform): the placeorder role includes an `aws_iam_role_policy` granting `states:StartExecution` on `aws_sfn_state_machine.fulfillment[each.key].arn`.

## Validation Evidence

```bash
API=<api_endpoint>
curl -s -X POST "$API/place-order" -d '{"items":["p1","p2"]}' ; echo
# {"executionArn":"arn:aws:states:...:execution:...","status":"STARTED"}

aws stepfunctions list-executions --state-machine-arn <sm-arn> --max-items 1
# executions[0].status == "SUCCEEDED"
```

The placeorder log no longer shows `AccessDeniedException`.

## Common Mistakes

- **Granting `states:StartExecution` on `*`** — works, but violates least privilege; scope to the ARN.
- **Adding the permission to the *state machine's* role instead of the *Lambda's* role** — the caller needs it, not the workflow.
- **Confusing this with a missing env var** — check the log; `AccessDeniedException` ≠ `KeyError`.
- **Forgetting IAM propagation** — new inline policies apply within seconds, but re-test if the first call still fails.

## Distinguish From Similar Failures

| Error in the placeorder log | Diagnosis |
|-----------------------------|-----------|
| `AccessDeniedException` on `states:StartExecution` | Caller's role lacks the permission (**this lab**) |
| `StateMachineDoesNotExist` | Wrong/stale state machine ARN in config |
| `KeyError` / `TypeError` | The input JSON assembly is broken, not IAM |
| Execution starts but fails immediately | The *state machine's* role or definition is the problem — a different lab (EM07) |

## Key Takeaways / Exam Angle

- **The service that *initiates* a workflow needs `states:StartExecution`** on the target ARN. Extremely common exam pattern.
- **Read the `AccessDeniedException`** — it names both the missing action and the resource ARN.
- **Least privilege:** scope Step Functions permissions to specific state-machine ARNs.
