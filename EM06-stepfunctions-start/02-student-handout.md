# EM06 — Orders Into the Void: Step Functions Won't Start — Student Handout

> **Region:** All lab resources are deployed in **US West (Oregon) — `us-west-2`**. Before running any AWS CLI command or opening the console, confirm your region is `us-west-2`. If you are in the wrong region, your resources will not exist and every command will fail.


## Lab Goals

- Understand how a Lambda starts an **AWS Step Functions** execution.
- Diagnose an `AccessDeniedException` on `states:StartExecution`.
- Confirm executions actually start.

## Scenario

At **Acme Retail**, placing an order is supposed to kick off a Step Functions workflow (charge, reserve inventory, notify). Right now every checkout returns a server error and **zero executions** show up in the state machine. Orders are disappearing into the void.

## Architecture

```
POST /place-order ─▶ Lambda (placeorder) ──(StartExecution?)──▶ Step Functions state machine
                                                                    (0 executions)
```

## Starting Symptom

1. `POST /place-order` → **HTTP 500**.
2. Step Functions → your state machine → **Executions** tab is **empty**.
3. The placeorder Lambda's log shows an **`AccessDeniedException`** referencing `states:StartExecution`.

## Time Limit

**25 minutes.**

## Guided Investigation Hints

1. A `500` from the checkout Lambda means the Lambda threw. Read its CloudWatch log.
2. `AccessDeniedException ... not authorized to perform: states:StartExecution` means the **Lambda's execution role** lacks permission to start the workflow.
3. The fix is an **IAM policy** on the Lambda's role granting `states:StartExecution` on the **specific state machine ARN** (least privilege — don't use `*`).
4. Confirm the Lambda is pointed at the right state machine (its `STATE_MACHINE_ARN` env var) before assuming it's purely IAM.

## Debugging Playbook (How a Pro Thinks)

An `AccessDeniedException` is not a mystery — it's a **fill-in-the-blank answer**. AWS tells you three things:

```
User: arn:...role/<WHO>  is not authorized to perform: <ACTION>  on resource: <RESOURCE-ARN>
```

Copy the action and resource straight into a policy statement on the *caller's* role. Done. The classic mistake is granting the permission to the wrong identity — remember: **the caller needs permission to start the workflow**; the state machine's own role is for what the workflow does *after* it starts.

Also verify config before IAM: one quick `aws lambda get-function-configuration --query 'Environment.Variables'` confirms the Lambda points at the right state machine ARN. Thirty seconds of config-checking prevents an hour of policy archaeology.

## Things to Check

- **CloudWatch Logs** for the placeorder function: the exact `AccessDeniedException` and which action/resource it names.
- **Lambda → placeorder → Configuration → Permissions → Execution role:** what actions does its policy allow?
- **Lambda → Configuration → Environment variables:** is `STATE_MACHINE_ARN` set and correct?
- **Step Functions → Executions:** any at all?

## Validation Criteria

You are done when:

1. `POST /place-order` → **200** with an `executionArn` in the response.
2. Step Functions → your state machine → **Executions** shows a new **`Succeeded`** execution.
3. Repeating checkout reliably starts one execution per call.

## Key Takeaways

- **To start a workflow, the caller's role needs `states:StartExecution` on that state machine's ARN.** Missing action = `AccessDeniedException`.
- **`AccessDeniedException` always names the action and resource** — read it; it tells you exactly what to grant.
- **Grant least privilege:** scope the permission to the one state machine ARN, not `*`.

## Reflection Questions

1. Why does the error surface as a `500` at the API instead of a Step Functions error?
2. What's the difference between `StartExecution` and `StartSyncExecution`, and when would you use each?
3. How would you scope this permission if the Lambda had to start several state machines?
