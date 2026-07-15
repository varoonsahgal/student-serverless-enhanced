# EM07 — The Broken Assembly Line: Step Functions Error Handling — Student Handout

> **Region:** All lab resources are deployed in **US West (Oregon) — `us-west-2`**. Before running any AWS CLI command or opening the console, confirm your region is `us-west-2`. If you are in the wrong region, your resources will not exist and every command will fail.


## Lab Goals

- Read a **failed** Step Functions execution and find the failing state.
- Add **`Retry`** and **`Catch`** to make a workflow resilient to a failing step.
- Understand graceful degradation vs. hard failure.

## Scenario

**Acme Retail**'s order workflow runs a payment step against a flaky third-party gateway. Right now, whenever the gateway hiccups, the **entire order workflow fails** — no retry, no fallback, no "flag for manual review." One transient blip and the customer's order is dead.

**Microcredential mapping:** this lab mirrors the error-handling requirement of **Challenge 5** of the assessment (the state machine must include `Catch` blocks so failures are handled, not fatal).

## Architecture

```
StartExecution ─▶ [ ProcessPayment (Task → Lambda) ] ─▶ (no Retry, no Catch)
                        │ throws
                        ▼
                   Execution FAILED
```

## Starting Symptom

1. `start-execution` on the state machine → the execution ends in **`FAILED`**.
2. The **execution graph** shows `ProcessPayment` red, with error `States.TaskFailed` (a `PaymentGatewayTimeout` from the Lambda).
3. There is **no retry** and **no fallback path** — the failure propagates straight to the top.

## Time Limit

**35 minutes.**

## Guided Investigation Hints

1. Open the failed execution and read the **event history** — which state failed, and with what error?
2. A `Task` state can declare **`Retry`** (re-attempt transient errors with backoff) and **`Catch`** (route a failure to a handling state instead of failing the whole workflow).
3. The payment step here fails every time (simulated outage). Retrying alone won't save it — you also need a **`Catch`** that routes to a "flag for manual review" state so the workflow **completes** instead of failing.
4. Edit the state machine **definition** (Amazon States Language). This is an ASL problem, not an IAM or code problem.

## Debugging Playbook (How a Pro Thinks)

For any failed Step Functions execution, go straight to the **event history** and read it like a stack trace:

1. Find the **first** `TaskFailed` / `ExecutionFailed` event (later events are fallout).
2. Note the state name, the `error` code, and the `cause` payload.
3. Ask: is this failure **transient** (timeouts, throttles, flaky dependency) or **terminal** (bad input, hard outage)?

That question decides your tool: **`Retry` buys time for transient errors; `Catch` buys grace for terminal ones.** A production-grade `Task` state usually carries both — retry a couple of times with backoff, then catch into a fallback that records the failure and lets the workflow end `SUCCEEDED`.

Reframe "success": an execution that **catches a payment failure, flags the order for review, and completes** is a success — the *system* handled it. Error handling in ASL is opt-in; a bare `Task` state is an unhandled exception waiting to kill the whole workflow.

## Things to Check

- **Step Functions → your state machine → Executions → (failed one) → Graph/Events:** which state, which error?
- **The state machine definition:** does `ProcessPayment` have `Retry` and `Catch`?
- **Does a fallback state exist** for failures (e.g., record/flag the order)?

## Validation Criteria

You are done when:

1. A new execution ends in **`SUCCEEDED`** even though the payment step still fails.
2. The final output shows the order was **flagged for review** (the `Catch` fallback ran), not silently lost.
3. The execution history shows the payment step was **retried** before the `Catch` fired.

## Key Takeaways

- **`Retry` handles transient errors; `Catch` handles "give up gracefully."** A robust `Task` usually has both.
- **Without `Catch`, one failing state fails the entire workflow.** Error handling is opt-in in ASL.
- **"Succeeded" should mean the workflow handled every outcome** — including failures — not that nothing went wrong.

## Reflection Questions

1. When is retrying pointless, and when is it the right first move?
2. Why might you *want* an execution to `SUCCEED` after catching a payment failure, rather than `FAIL`?
3. How would you send caught failures to an SQS "needs-review" queue from the `Catch` branch?
