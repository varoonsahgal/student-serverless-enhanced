# EM10 — Silent Receipts — Solution Handout

> Instructor answer key.

## Original Symptom

The notification Lambda errors on publish; the log shows an SNS `NotFound` (topic does not exist); the inbox subscriber never receives anything.

## Root Cause

The Lambda's **`TOPIC_ARN` environment variable** points to a **non-existent topic** (a typo'd ARN — the real topic name with an extra suffix). `sns.publish(TopicArn=...)` therefore fails with `NotFoundException`. The function's `sns:Publish` permission and code are correct; it's simply addressing the wrong topic.

## Exact Fix

Set `TOPIC_ARN` to the real orders topic ARN.

### Console

1. SNS → your orders topic → copy the **ARN**.
2. Lambda → send-notification function → **Configuration → Environment variables → Edit**.
3. Set `TOPIC_ARN` to the real ARN → **Save**.

### CLI

```bash
FN=<send-notification fn>
REAL_ARN=<orders topic arn>   # aws sns list-topics

aws lambda update-function-configuration \
  --function-name "$FN" \
  --environment "Variables={TOPIC_ARN=$REAL_ARN}"
```

> Permanent fix (solution Terraform): `TOPIC_ARN = aws_sns_topic.orders[each.key].arn` (the broken stack appended `-typo`).

## Validation Evidence

```bash
FN=<fn>; INBOX=<inbox queue url>
aws lambda invoke --function-name "$FN" \
  --payload '{"orderId":"o1"}' --cli-binary-format raw-in-base64-out /tmp/o.json
cat /tmp/o.json    # {"messageId":"...."}

aws sqs receive-message --queue-url "$INBOX" --wait-time-seconds 5
# a message whose body contains {"orderId":"o1","status":"CONFIRMED"}
```

Log shows `published messageId ...` — no `NotFound`.

## Common Mistakes

- **Assuming it's an IAM problem** and adding broad `sns:Publish` on `*` — the error was `NotFound`, not `AuthorizationError`.
- **Fixing the topic name in the code** instead of the env var — the value is externalized as config; fix the env var.
- **Declaring success because the Lambda "ran"** — verify the subscriber actually received the message.

## Distinguish From Similar Failures

| Error | Diagnosis |
|-------|-----------|
| `NotFoundException` on publish | Topic ARN is wrong/nonexistent — config bug (**this lab**) |
| `AuthorizationErrorException` | Topic exists but role lacks `sns:Publish` — IAM bug |
| Publish succeeds, subscriber gets nothing | Wrong-but-existing topic, or a filter policy drops it (EM03) |
| Publish succeeds, email users get nothing | Subscription still `Pending confirmation` |

## Key Takeaways / Exam Angle

- **`NotFound` on an SNS/SQS operation = wrong resource ARN (config), not permissions.** Learn to read the error type.
- **Externalized config (env vars) is a common failure surface** — a stale ARN breaks an otherwise-correct function.
- **Verify delivery end-to-end** with a subscriber; "no exception" is not proof of delivery.
