# EM15 — Black Friday Capstone: Multi-Fault Recovery — Student Handout

> **Region:** All lab resources are deployed in **US West (Oregon) — `us-west-2`**. Before running any AWS CLI command or opening the console, confirm your region is `us-west-2`. If you are in the wrong region, your resources will not exist and every command will fail.


## Lab Goals

- Triage a **multi-service** failure end to end under time pressure.
- Apply everything from the earlier labs: payload format, IAM actions, resource scoping, config.
- Restore the full **checkout → save → workflow → notify** path.

## Scenario

It's **Black Friday** at **Acme Retail**. The lead engineer is gone and the checkout pipeline is broken in **four independent places** across four services. Customers hit "Place order" and nothing works. You have one job: get one order to flow cleanly from the API all the way to a confirmation notification — and prove it.

**Microcredential mapping:** this lab mirrors the assessment's **Final End-to-End Validation** — one order must flow from API to notification, and 'the platform is operational' means every downstream effect is proven, not assumed.

## Architecture

```
POST /checkout ─▶ API Gateway (HTTP) ─▶ Lambda (placeorder)
                                            │  1) write order  ─▶ DynamoDB (orders)
                                            │  2) start workflow ─▶ Step Functions ─▶ Lambda (notify)
                                            ▼                                              │ publish
                                     (returns execution)                                  ▼
                                                                        SNS topic ─▶ inbox (SQS)
```

## Starting Symptom

Working through the flow, you'll uncover the faults **in sequence** — fixing one reveals the next:

1. `POST /checkout` → **HTTP 500** immediately (before any order logic).
2. After that: the order **isn't written** to DynamoDB (`AccessDenied` on write).
3. After that: **no Step Functions execution** starts (`AccessDenied`).
4. After that: `POST /checkout` returns `200`, but the **inbox never receives** a confirmation.

## Time Limit

**75 minutes.**

## Guided Investigation Hints

1. **The door (500):** an HTTP API proxy `500` usually means the Lambda threw. Check the **integration payload format version** vs. what the handler reads (`requestContext.http` is 2.0).
2. **The save (AccessDenied on write):** read the log — is it `dynamodb:PutItem`? Compare the role's allowed **actions** to what the code does.
3. **The workflow (no execution):** the placeorder role must be allowed to `states:StartExecution` on the state machine.
4. **The receipt (no notification):** the flow returns `200` but the **notify** Lambda (inside the workflow) fails. Check *its* logs and its `TOPIC_ARN`.

Fix them one at a time and re-test after each.

## Debugging Playbook (How a Pro Thinks)

Multi-fault incidents need **incident discipline**, not heroics:

1. **Classify before you touch.** Each error signature routes to a family of fixes: `500` → code/integration contract; `AccessDenied` → IAM (read WHO/ACTION/RESOURCE); `NotFound` → config/ARN; silence → wiring or filtering.
2. **Fix the outermost blocker first.** You can't diagnose the order-write while the API 500s at the front door. Peel layers from the client inward.
3. **Re-test the whole flow after every fix.** Each repair reveals the next fault. One `curl` after each change is your heartbeat.
4. **Keep a fault log** (symptom → evidence → fix → proof). Under time pressure, written state beats memory.
5. **Never trust a `200`.** The API returning success only proves the *first* hop worked. Verify every side effect: the DynamoDB item, the execution status, the message in the inbox queue.

Every fault in this capstone is a rerun of an earlier lab (EM01, EM13, EM06, EM10). If you get stuck, ask: *which lab does this error signature belong to?*

## Things to Check

- API integration **payload format version**.
- placeorder role: `dynamodb:PutItem`? `states:StartExecution`?
- notify Lambda logs; its `TOPIC_ARN` vs. the real topic ARN.
- The **inbox** SQS queue for the final confirmation.

## Validation Criteria

You are done when a single `POST /checkout`:

1. Returns **`200`** with an `orderId` and an `execution` ARN.
2. Writes the order to **DynamoDB** (visible via `get-item`).
3. Starts a **Step Functions** execution that **`Succeeds`**.
4. Results in a confirmation message in the **inbox** SQS queue.

## Key Takeaways

- **Multi-fault incidents are layered** — fix the outermost blocker first, then re-test to reveal the next.
- **Status codes and error types route you:** `500` → code/integration; `AccessDenied` → IAM (action or resource); `NotFound` → wrong ARN/config.
- **"Returns 200" is not "works."** Verify every downstream effect (DynamoDB item, execution status, delivered notification).

## Reflection Questions

1. Which fault was hardest to see, and why? What observability would have surfaced it faster?
2. How would you write a single end-to-end smoke test that catches all four faults at once?
3. In a real incident, how would you decide the order to fix multiple independent failures?
