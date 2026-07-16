# EM12 — Flying Blind — Solution Handout

> Instructor answer key.

## Original Symptom

The Lambda errors on invoke, but its CloudWatch log group is empty — no traceback to work from.

## Root Causes (two layers)

| # | Fault | Effect |
|---|-------|--------|
| 1 | Execution role lacks `logs:CreateLogStream` / `logs:PutLogEvents` | function runs but writes **no logs** (flying blind) |
| 2 | Handler reads `event["order"]["id"]` but is invoked with `{"orderId": ...}` | `KeyError` → `500`, invisible until logging works |

### Why it happened

Someone wrote a bespoke least-privilege role and forgot the logging permissions, so the underlying `KeyError` produced no visible trace.

## Exact Fix

### Layer 1 — restore logging

**Console:** Lambda → function → **Configuration → Permissions** → execution role → **Attach policies** → `AWSLambdaBasicExecutionRole`. Invoke again and read the traceback.

**CLI:**
```bash
aws iam attach-role-policy --role-name <fn-role> \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
```

### Layer 2 — fix the revealed bug

The traceback shows `KeyError: 'order'`. The handler should read `event["orderId"]`:

```python
order_id = event["orderId"]   # was event["order"]["id"]
```

Redeploy (or re-run the solution Terraform, which ships both fixes).

> Permanent fix (solution Terraform): the role attaches `AWSLambdaBasicExecutionRole` **and** `lambda.py` reads `event["orderId"]`.

## Validation Evidence

```bash
FN=<fn>
aws lambda invoke --function-name "$FN" \
  --payload '{"orderId":"o1"}' --cli-binary-format raw-in-base64-out /tmp/o.json
cat /tmp/o.json    # {"orderId":"o1","status":"OK"}

aws logs tail "/aws/lambda/$FN" --since 2m   # now shows log events
```

## Common Mistakes

- **Trying to fix the code first** — impossible without logs. Restore observability first.
- **Assuming the empty log group means the function never ran** — it ran; it just couldn't log.
- **Granting `logs:*` on `*`** broadly when the managed `AWSLambdaBasicExecutionRole` is the clean, standard choice.

## Distinguish From Similar Failures

| Invocations metric | Log group | Diagnosis |
|--------------------|-----------|-----------|
| 0 | Empty | Never invoked — wiring/trigger problem, not logging |
| > 0 | Empty | Ran but can't write logs — missing `logs:*` permissions (**this lab, layer 1**) |
| > 0 | Events present with tracebacks | Normal debugging — read the traceback (**this lab, layer 2**) |
| > 0 | Empty here, events in another group | Custom log-group configuration points elsewhere |

## Key Takeaways / Exam Angle

- **Lambda logging requires `logs:CreateLogGroup/CreateLogStream/PutLogEvents`** — usually via `AWSLambdaBasicExecutionRole`. No logs = missing these.
- **Fix observability before debugging logic.**
- **A silent function that errors is an IAM/logging gap**, not (yet) proof the code is fine.
