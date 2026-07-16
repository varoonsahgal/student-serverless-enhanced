# EM07 — The Broken Assembly Line — Solution Handout

> Instructor answer key.

## Original Symptom

Every execution ends `FAILED` at `ProcessPayment` with `States.TaskFailed`.

## Root Cause

The `ProcessPayment` `Task` state has **no `Retry` and no `Catch`**. The payment Lambda raises an exception (simulating a gateway outage), so `States.TaskFailed` propagates to the top and the whole execution fails. There is no fallback path to complete the order gracefully.

## Exact Fix

Edit the state machine **definition** so `ProcessPayment` retries transient errors and catches failures into a fallback state that flags the order for manual review.

### Fixed definition (ASL)

```json
{
  "Comment": "Acme order fulfillment with error handling",
  "StartAt": "ProcessPayment",
  "States": {
    "ProcessPayment": {
      "Type": "Task",
      "Resource": "<payment-lambda-arn>",
      "Retry": [
        { "ErrorEquals": ["States.ALL"], "IntervalSeconds": 1, "MaxAttempts": 2, "BackoffRate": 2.0 }
      ],
      "Catch": [
        { "ErrorEquals": ["States.ALL"], "Next": "HandleFailure" }
      ],
      "Next": "Done"
    },
    "HandleFailure": {
      "Type": "Pass",
      "Result": { "status": "FLAGGED_FOR_REVIEW" },
      "End": true
    },
    "Done": {
      "Type": "Pass",
      "Result": { "status": "PAID" },
      "End": true
    }
  }
}
```

### Console

Step Functions → your state machine → **Edit** → paste the definition above (substituting the real payment Lambda ARN) → **Save**.

### CLI

```bash
aws stepfunctions update-state-machine \
  --state-machine-arn <sm-arn> \
  --definition file://fixed-definition.json
```

> Permanent fix (solution Terraform): the `aws_sfn_state_machine.fulfillment` definition includes `Retry` + `Catch` and the `HandleFailure` / `Done` states.

## Validation Evidence

```bash
SM=<sm-arn>
EXEC=$(aws stepfunctions start-execution --state-machine-arn "$SM" \
  --input '{"orderId":"o-1","amount":42}' --query executionArn --output text)
sleep 5
aws stepfunctions describe-execution --execution-arn "$EXEC" \
  --query '{status:status,output:output}'
# status = "SUCCEEDED", output contains "FLAGGED_FOR_REVIEW"
```

The execution **event history** shows `ProcessPayment` attempted, retried, then the `Catch` transition to `HandleFailure`, ending `SUCCEEDED`.

## Common Mistakes

- **Adding `Retry` but not `Catch`** — with a permanently failing step, retries exhaust and the workflow still `FAILS`. You need `Catch` to complete gracefully.
- **Catching to a state that also `End`s in failure** — the `Catch` target should resolve the workflow (Pass/record), not re-raise.
- **Editing the payment Lambda to "not fail"** — that sidesteps the lesson; the point is resilient orchestration, not a bug-free gateway.
- **Using `ErrorEquals: ["States.TaskFailed"]` only** and missing other error types — `States.ALL` is safest as the last catcher.

## Distinguish From Similar Failures

| Event-history error | Diagnosis |
|---------------------|-----------|
| `States.TaskFailed` with a Lambda exception in `cause` | The task's code threw — handle with `Retry`/`Catch` (**this lab**) |
| `States.Timeout` | Task exceeded `TimeoutSeconds` — tune the timeout or the worker |
| `Lambda.ServiceException` / throttling errors | Transient AWS-side — this is exactly what `Retry` with backoff exists for |
| `States.Runtime` on a state transition | Broken ASL (bad JSONPath/ResultPath), not the worker |
| Execution never starts | Caller-side problem (see EM06), not error handling |

## Key Takeaways / Exam Angle

- **`Retry` + `Catch` are the core Step Functions resilience primitives.** The exam expects you to know `ErrorEquals`, `MaxAttempts`, `BackoffRate`, and `Next`.
- **A `Catch` lets a workflow `SUCCEED` after handling a failure** — essential for "flag for review / send to DLQ" patterns.
- **Error handling in ASL is opt-in** — no `Catch` means one bad step kills everything.
