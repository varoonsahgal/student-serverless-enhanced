# EM08 — Dead Letters: SQS DLQ & Poison Messages — Student Handout

> **Region:** All lab resources are deployed in **US West (Oregon) — `us-west-2`**. Before running any AWS CLI command or opening the console, confirm your region is `us-west-2`. If you are in the wrong region, your resources will not exist and every command will fail.


## Lab Goals

- Understand SQS **redrive policy** and **dead-letter queues (DLQ)**.
- Diagnose a "poison message" that retries forever.
- Prove that unprocessable messages are quarantined.

## Scenario

**Acme Retail** funnels failed-order events into an SQS queue that a Lambda drains. One malformed order got in and now it **retries endlessly** — the same message reappears every few seconds, spamming the logs and blocking clean processing. There's nowhere for bad messages to go.

**Microcredential mapping:** this lab mirrors the error-queue requirement of **Challenge 5** of the assessment (failed-order information must be captured for later investigation or reprocessing, not retried forever).

## Architecture

```
send-message ─▶ SQS order-errors ─▶ Lambda consumer
                     ▲                    │ throws on poison msg
                     └────────────────────┘  (redelivered forever — no DLQ)
```

## Starting Symptom

1. Sending a normal message → processed once, gone. Good.
2. Sending a **poison** message (`{"poison": true}`) → the consumer throws, and the message **comes back** again and again. Its `ApproximateReceiveCount` keeps climbing.
3. There is **no dead-letter queue** — nowhere for the bad message to land.

## Time Limit

**30 minutes.**

## Guided Investigation Hints

1. When a Lambda triggered by SQS throws, the message returns to the queue after the **visibility timeout** and is retried. Without a limit, this is **forever** (until retention expires).
2. An SQS queue can have a **redrive policy**: after `maxReceiveCount` failed receives, the message is moved to a **dead-letter queue** instead of being retried again.
3. Check the source queue's **Dead-letter queue** setting and whether a DLQ even exists.
4. Test the behavior:
   ```bash
   aws sqs send-message --queue-url <main-q> --message-body '{"poison": true}'
   # watch it reappear; check the (missing) DLQ
   ```

## Debugging Playbook (How a Pro Thinks)

When the same message keeps reappearing, check its vital signs:

```bash
aws sqs receive-message --queue-url $Q --attribute-names ApproximateReceiveCount
```

A climbing `ApproximateReceiveCount` = a **poison message loop**. Now check the queue's redrive policy — if there isn't one, retries are unbounded (until retention expires, spamming logs the whole time).

Sizing intuition for `maxReceiveCount`: too low (1–2) and a routine transient blip dead-letters good messages; too high (100) and a poison message burns compute for hours. **3–5 is the usual sweet spot** — enough retries to survive a hiccup, few enough to quarantine real poison fast.

Second invariant: **visibility timeout ≥ consumer processing time** (for Lambda, ≥ function timeout; AWS recommends ~6×). If the message becomes visible again while it's still being processed, you get *duplicate* deliveries that look exactly like this bug but aren't.

## Things to Check

- **SQS → order-errors queue → Dead-letter queue** section: is a redrive policy configured?
- Is there a **DLQ** at all?
- **CloudWatch Logs** for the consumer: is the same message ID failing repeatedly?
- **SQS metrics:** `ApproximateReceiveCount` on the stuck message; `ApproximateNumberOfMessagesVisible`.

## Validation Criteria

You are done when:

1. A poison message is retried a **bounded** number of times (e.g., 3) and then lands in the **DLQ**.
2. The **main queue drains** — the poison message no longer reappears there.
3. Normal messages still process successfully and do **not** end up in the DLQ.

## Key Takeaways

- **A DLQ + `maxReceiveCount` bounds retries** and quarantines poison messages so they stop blocking the queue.
- **Without a redrive policy, a failing message retries until retention expires** — wasteful and noisy.
- **DLQs are for investigation, not deletion** — you inspect/redrive them later.

## Reflection Questions

1. How do you choose a good `maxReceiveCount` — too low vs. too high?
2. Why must the source queue's **visibility timeout** be at least as long as the consumer's processing time?
3. How would you later re-process (redrive) messages sitting in the DLQ?
