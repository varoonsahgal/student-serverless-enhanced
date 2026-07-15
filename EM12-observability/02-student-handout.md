# EM12 — Flying Blind: CloudWatch Observability — Student Handout

> **Region:** All lab resources are deployed in **US West (Oregon) — `us-west-2`**. Before running any AWS CLI command or opening the console, confirm your region is `us-west-2`. If you are in the wrong region, your resources will not exist and every command will fail.


## Lab Goals

- Recognize when a Lambda produces **no logs at all** and why.
- Fix logging permissions so failures become visible.
- Then use the newly-visible logs to fix the real bug.

## Scenario

**Acme Retail**'s order-intake Lambda returns errors, but the on-call engineer is **flying blind**: CloudWatch shows nothing. You can't fix what you can't see — first restore observability, then find the actual defect the logs reveal.

**Microcredential mapping:** this lab trains the assessment's cross-cutting requirement: *diagnose failures by using Amazon CloudWatch Logs*. Every challenge assumes you can see your errors — this lab is about what to do when you can't.

## Architecture

```
invoke (order) ─▶ Lambda (order-intake) ──▶ (returns 500)
                        │
                        └─▶ CloudWatch Logs  ← empty! (no permission to write)
```

## Starting Symptom

1. Invoking the Lambda returns a **function error / 500**.
2. The function's CloudWatch log group exists but has **no log events** — as if nothing ran.
3. You have no traceback to work from.

## Time Limit

**30 minutes.**

## Guided Investigation Hints

1. A Lambda writes logs only if its **execution role** allows `logs:CreateLogStream` and `logs:PutLogEvents`. Without them, the function runs but **emits no logs**.
2. Step 1 is to restore logging (attach the basic execution permissions), invoke again, and **read the traceback**.
3. The traceback will point at a **code bug** (a wrong key in the event). Fix that second.
4. This lab has **two layers**: observability, then the real defect. Fix them in that order.

## Debugging Playbook (How a Pro Thinks)

"No logs" has exactly three causes. CloudWatch **metrics** discriminate between them — metrics are emitted by the Lambda *service*, so they record even when the function can't write logs:

| Invocations metric | Log group | Diagnosis |
|--------------------|-----------|-----------|
| 0 | empty | Function never invoked → wiring/trigger problem |
| > 0 | empty | Ran but can't write → **missing `logs:*` permissions** |
| > 0 | events elsewhere | Logging to a different/custom log group |

This lab is the middle row. The deeper lesson is **ordering**: observability is a *prerequisite*, not a nice-to-have. You cannot debug what you cannot see, so the first fix is always "make failures visible," and only then chase the actual bug the logs reveal. In production this is why logging permissions belong in your baseline role template — a bespoke least-privilege role that forgets `logs:` turns every future incident into archaeology.

## Things to Check

- **Lambda → Configuration → Permissions → execution role:** does it allow `logs:CreateLogStream` / `logs:PutLogEvents`?
- **CloudWatch → Log groups →** the function's group: any streams/events?
- After logging works: the **exception type and the key** it references.

## Validation Criteria

You are done when:

1. Invoking the Lambda now **writes logs** (you can see a traceback or success message).
2. The **real bug** is fixed and the function returns **`200`** with the order id.
3. A malformed invoke still logs a clear error (observability holds).

## Key Takeaways

- **No logs at all = the role can't write logs.** Fix `logs:*` permissions before anything else.
- **Observability is a prerequisite for debugging** — restore it first, then diagnose.
- **`AWSLambdaBasicExecutionRole`** is the standard managed policy that grants Lambda its CloudWatch Logs permissions.

## Reflection Questions

1. Why might a hand-crafted least-privilege role accidentally omit logging permissions?
2. How would structured (JSON) logging have sped up finding the real bug?
3. What alarm would tell you a function is failing even when it isn't logging?
