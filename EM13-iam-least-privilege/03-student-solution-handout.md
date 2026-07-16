# EM13 — The Access-Denied Maze — Solution Handout

> Instructor answer key.

## Original Symptom

`AccessDeniedException` on `dynamodb:PutItem` for the `orders` table, even though the role has a `PutItem` allow.

## Root Cause

The role's `dynamodb:PutItem` / `GetItem` statement scopes `Resource` to a **different table ARN** — the intended name minus one character (`...-em13-order` instead of `...-em13-orders`). The action is allowed, but on a table the Lambda never touches, so calls against the real `orders` table are denied.

## Exact Fix

Correct the policy's `Resource` to the real orders-table ARN (keep it scoped — don't use `*`).

### Console

1. IAM → the Lambda's role → the inline policy → **Edit**.
2. In the `dynamodb:PutItem`/`GetItem` statement, set `Resource` to the **orders table ARN** (copy from DynamoDB → table → Overview → ARN).
3. Save.

### CLI

```bash
ROLE=<order-writer role name>
TABLE_ARN=<real orders table arn>   # aws dynamodb describe-table --table-name <t> --query Table.TableArn --output text

aws iam put-role-policy --role-name "$ROLE" --policy-name orders-access \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"dynamodb:PutItem\",\"dynamodb:GetItem\"],\"Resource\":\"$TABLE_ARN\"}]}"
```

> Permanent fix (solution Terraform): the policy `Resource` references `aws_dynamodb_table.orders[each.key].arn` directly, so it can never drift from the real ARN.

## Validation Evidence

```bash
FN=<fn>
aws lambda invoke --function-name "$FN" \
  --payload '{"orderId":"o1"}' --cli-binary-format raw-in-base64-out /tmp/o.json
cat /tmp/o.json   # {"orderId":"o1","status":"SAVED"}

aws dynamodb get-item --table-name <orders table> \
  --key '{"orderId":{"S":"o1"}}'
# returns the item
```

No `AccessDeniedException` in the logs.

## Common Mistakes

- **Widening `Resource` to `"*"`** — makes the error disappear but breaks least privilege. Fix the ARN.
- **Adding `PutItem` again** thinking the action was missing — it wasn't; the resource was wrong.
- **Matching the ARN region/account but not the table name** — the table name is the mismatch.

## Distinguish From Similar Failures

| Denial flavor | Fingerprint | Fix |
|---------------|-------------|-----|
| Action missing entirely | No statement allows `dynamodb:PutItem` | Add the action |
| Action allowed, wrong `Resource` ARN | Policy ARN ≠ error ARN (**this lab**) | Correct the ARN |
| Explicit `Deny` somewhere | Denied despite a clear Allow | Hunt the Deny (it always wins) |
| SCP / permission boundary | Error mentions "with an explicit deny in a service control policy" or boundary | Org/boundary level, not the role policy |

## Key Takeaways / Exam Angle

- **`AccessDeniedException` binds an action to a resource** — an allowed action on the wrong ARN is denied.
- **Reference resources by attribute in IaC** (`aws_dynamodb_table.orders.arn`) so policy ARNs never drift.
- **Correct the scope; don't broaden to `*`.**
