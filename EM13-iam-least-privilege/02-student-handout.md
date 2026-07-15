# EM13 — The Access-Denied Maze: IAM Least Privilege — Student Handout

> **Region:** All lab resources are deployed in **US West (Oregon) — `us-west-2`**. Before running any AWS CLI command or opening the console, confirm your region is `us-west-2`. If you are in the wrong region, your resources will not exist and every command will fail.


## Lab Goals

- Read an `AccessDeniedException` and extract the **action** and **resource**.
- Distinguish a **missing action** from a **wrong resource ARN**.
- Fix an over-scoped/mis-scoped IAM policy.

## Scenario

**Acme Retail**'s order-writer Lambda can't save orders. It throws `AccessDenied` on DynamoDB — yet someone "already gave it DynamoDB permissions." The permission exists, but it's pointed at the **wrong table**. Welcome to the access-denied maze.

**Microcredential mapping:** the assessment pre-builds its IAM roles for you, but every challenge fails exactly like this lab when a policy's action or resource is wrong. This is the IAM debugging skill underneath all seven challenges.

## Architecture

```
invoke (order) ─▶ Lambda (order-writer) ──PutItem──▶ DynamoDB "orders" table
                        role allows PutItem on ... a DIFFERENT table ARN
```

## Starting Symptom

1. Invoking the Lambda returns a **function error**.
2. The log shows `AccessDeniedException: ... not authorized to perform: dynamodb:PutItem on resource: .../orders`.
3. The role *does* have a `dynamodb:PutItem` allow — but the Deny is real.

## Time Limit

**25 minutes.**

## Guided Investigation Hints

1. An `AccessDeniedException` names both the **action** (`dynamodb:PutItem`) and the **resource** (the table ARN the call targeted). Read both.
2. Compare the **resource ARN in the error** to the **resource ARN in the policy**. If the policy allows the action but on a *different* ARN, you get denied.
3. Look closely at the table **name** in each — a one-character difference (e.g., `order` vs `orders`) is enough.
4. Fix the policy's `Resource` to match the real table's ARN (least privilege — don't switch to `*`).

## Debugging Playbook (How a Pro Thinks)

Read an `AccessDeniedException` as three fields, and check them **in order**:

1. **Principal** — is this even the role you think is running? (Wrong function/role happens more than you'd think.)
2. **Action** — does any statement allow it?
3. **Resource** — does the statement's `Resource` ARN match *the ARN in the error message*, character for character?

The trap in this lab is step 3: the action is allowed, so a quick skim of the policy looks fine. **An allowed action on the wrong resource is still a denial.** Diff the two ARNs like strings, not like ideas — `...-order` vs `...-orders` hides in plain sight.

Prevention beats debugging: in IaC, never hand-type an ARN into a policy. Reference the resource attribute (`aws_dynamodb_table.orders.arn`) so the policy *cannot* drift from the real resource. Every hand-typed ARN is a future incident.

## Things to Check

- **CloudWatch Logs:** the exact `AccessDeniedException` — note the resource ARN it targeted.
- **IAM → the Lambda's role → policy JSON:** what `Resource` does the `dynamodb:PutItem` statement allow?
- **DynamoDB → your orders table → ARN:** the real value.
- Do the two ARNs match **exactly**?

## Validation Criteria

You are done when:

1. Invoking the Lambda returns **`200`** and writes the item.
2. `AccessDeniedException` no longer appears in the logs.
3. The policy still scopes to the **specific** orders-table ARN (not `*`).

## Key Takeaways

- **`AccessDeniedException` = action + resource.** An allowed action on the *wrong resource* is still denied.
- **Resource ARN typos are a classic least-privilege bug** — the intent was right, the target was wrong.
- **Fix by correcting the ARN, not by widening to `*`.**

## Reflection Questions

1. How would the error differ if the action (`PutItem`) were missing entirely vs. the resource being wrong?
2. Why is `Resource: "*"` a tempting but poor fix here?
3. How could you catch ARN mismatches before deploy (e.g., referencing the resource by attribute in IaC)?
