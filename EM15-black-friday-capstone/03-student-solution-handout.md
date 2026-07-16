# EM15 — Black Friday Capstone — Solution Handout

> Instructor answer key. Four independent faults across four services.

## Original Symptom

`POST /checkout` fails; layered failures surface as each is fixed: `500` → `AccessDenied` (write) → `AccessDenied` (workflow) → no notification.

## Root Causes

| # | Service | Fault | Error | Fix |
|---|---------|-------|-------|-----|
| A | API Gateway | integration `payload_format_version = "1.0"` | placeorder `KeyError` → `500` | set `2.0` |
| B | IAM / DynamoDB | placeorder role allows `GetItem` but not `PutItem` | `AccessDenied` on `dynamodb:PutItem` | add `dynamodb:PutItem` |
| C | IAM / Step Functions | placeorder role missing `states:StartExecution` | `AccessDenied` on `states:StartExecution` | add `states:StartExecution` on the SM ARN |
| D | Config / SNS | notify Lambda `TOPIC_ARN` = real ARN + `-typo` | `NotFound` on publish; inbox empty | set `TOPIC_ARN` to the real topic ARN |

## Exact Fixes

### A — Payload format (API Gateway)

```bash
aws apigatewayv2 update-integration --api-id <api> --integration-id <int> --payload-format-version 2.0
```
(Console: HTTP API → Integrations → edit → Payload format version → `2.0`.)

### B — DynamoDB PutItem (placeorder role)

Add `dynamodb:PutItem` to the placeorder role's DynamoDB statement (scoped to the orders-table ARN).

### C — StartExecution (placeorder role)

```bash
aws iam put-role-policy --role-name <placeorder-role> --policy-name start-wf \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"states:StartExecution","Resource":"<sm-arn>"}]}'
```

### D — Notify topic ARN (config)

```bash
aws lambda update-function-configuration --function-name <notify-fn> \
  --environment "Variables={TOPIC_ARN=<real topic arn>}"
```

> Permanent fix (solution Terraform): payload format `2.0`; placeorder policy includes `PutItem` **and** `states:StartExecution`; notify `TOPIC_ARN` = the real topic ARN.

## Validation Evidence

```bash
API=<api_endpoint>
curl -s -X POST "$API/checkout" -d '{"orderId":"bf-1"}' ; echo
# {"orderId":"bf-1","execution":"arn:aws:states:...:execution:..."}

aws dynamodb get-item --table-name <orders> --key '{"orderId":{"S":"bf-1"}}'   # item present
aws stepfunctions list-executions --state-machine-arn <sm> --max-items 1       # SUCCEEDED
aws sqs receive-message --queue-url <inbox> --wait-time-seconds 5              # confirmation for bf-1
```

## Common Mistakes

- **Fixing faults out of order / not re-testing** — each fix reveals the next; re-run `POST /checkout` each time.
- **Declaring victory at `200`** — the `200` appears once C is fixed, but D (notification) can still be broken. Verify the inbox.
- **Broadening IAM to `*`** to make errors vanish — scope to the specific ARNs.
- **Editing the notify topic name in code** instead of the env var.

## Distinguish From Similar Failures

Every fault in this capstone is a rerun of an earlier lab — match the signature:

| Signature | Fault | Rehearsed in |
|-----------|-------|--------------|
| `500` + `KeyError` on `requestContext.http` | A — payload format 1.0 vs 2.0 | EM01 |
| `AccessDenied` on `dynamodb:PutItem` (action missing) | B — IAM action gap | EM13 (resource variant) |
| `AccessDenied` on `states:StartExecution` | C — caller can't start the workflow | EM06 |
| `NotFound` on SNS publish | D — stale `TOPIC_ARN` config | EM10 |

## Key Takeaways / Exam Angle

- **Layered incidents:** fix the outermost blocker, re-test, repeat. Each layer has its own signal (`500`, `AccessDenied`, `NotFound`).
- **Match the error to the fix:** integration/code (`500`), IAM action or resource (`AccessDenied`), config/ARN (`NotFound`).
- **End-to-end validation** across all four services is the only real proof of "fixed."
