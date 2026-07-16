# EM10 — Silent Receipts: SNS Order Notifications — Student Handout

> **Region:** All lab resources are deployed in **US West (Oregon) — `us-west-2`**. Before running any AWS CLI command or opening the console, confirm your region is `us-west-2`. If you are in the wrong region, your resources will not exist and every command will fail.


## Lab Goals

- Diagnose a Lambda that fails to publish to SNS.
- Recognize a **configuration** (environment variable) bug vs. a permissions bug.
- Confirm end-to-end delivery via a subscriber.

## Scenario

**Acme Retail** customers place orders successfully, but **no confirmation emails go out**. The notification Lambda runs, logs an error, and moves on — receipts are vanishing silently. With the sale live, customers think their orders failed.

## Architecture

```
invoke (order) ─▶ Lambda (send-notification) ──publish──▶ SNS topic ─▶ inbox (SQS subscriber)
                                                   ▲
                                            wrong TOPIC_ARN?
```

## Starting Symptom

1. Invoking the notification Lambda returns a **function error** (no `messageId`).
2. The CloudWatch log shows an SNS error indicating the **target topic does not exist / cannot be found**.
3. The **inbox** subscriber queue never receives a message.

## Time Limit

**25 minutes.**

## Guided Investigation Hints

1. Read the log: an SNS publish that fails with a "topic does not exist" / `NotFound` error points at the **topic ARN the code is using**, not at IAM.
2. Compare the Lambda's `TOPIC_ARN` **environment variable** to the **actual** topic ARN (SNS console → your topic → ARN). Look for a typo or a stale name.
3. This is a **config** bug: the code and permissions are fine; it's publishing to the wrong address.
4. Test after fixing:
   ```bash
   aws lambda invoke --function-name <fn> --payload '{"orderId":"o1"}' --cli-binary-format raw-in-base64-out /tmp/o.json
   aws sqs receive-message --queue-url <inbox-url> --wait-time-seconds 5
   ```

## Debugging Playbook (How a Pro Thinks)

Exception classes sort SNS publish failures into different fixes:

| Error | Real meaning | Fix surface |
|-------|--------------|-------------|
| `NotFoundException` | The topic ARN you used doesn't exist | Config (env var / hardcoded ARN) |
| `AuthorizationErrorException` | Topic exists; you may not publish | IAM (`sns:Publish`) |
| No error, but nothing arrives | Delivered to the *wrong existing* topic, or filtered | Compare ARNs; check subscriptions |

The third row is the nastiest: a stale-but-still-existing ARN fails **silently**. That's why pros verify **end-to-end with the subscriber** (here, the inbox SQS queue), not just "the Lambda didn't throw."

Habit worth stealing: **log the returned `MessageId` on every publish.** It's your receipt — proof the publish happened, and a correlation key for tracing delivery downstream.

## Things to Check

- **Lambda → Configuration → Environment variables → `TOPIC_ARN`.**
- **SNS → your orders topic → ARN** (the real value).
- **CloudWatch Logs:** the exact SNS error.
- **SQS inbox queue:** any messages?

## Validation Criteria

You are done when:

1. Invoking the Lambda returns a **`messageId`** (publish succeeded).
2. The **inbox** subscriber queue receives the order confirmation message.
3. The log shows a successful publish with the message ID (no `NotFound`).

## Key Takeaways

- **A wrong `TOPIC_ARN` env var is a config bug, not an IAM bug** — the log's error type tells you which.
- **`NotFound` on publish = wrong/nonexistent topic ARN**; `AuthorizationError` would mean missing `sns:Publish`. Different symptoms, different fixes.
- **Always verify end-to-end with a real subscriber**, not just "the Lambda didn't throw."

## Reflection Questions

1. How would the symptom differ if the bug were a missing `sns:Publish` permission instead of a wrong ARN?
2. Why is logging the returned `MessageId` a good habit for publish operations?
3. How could you catch a stale topic ARN before it reaches production?
