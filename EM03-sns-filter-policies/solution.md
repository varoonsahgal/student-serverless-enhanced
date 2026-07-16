# EM03 — Lost in the Fan-Out — Solution Handout

> Instructor answer key.

## Original Symptom

Events with `order_type = standard` reach the standard SQS queue; events with `order_type = priority` never reach the priority queue. No errors.

## Root Cause

The **priority** subscription's filter policy uses the attribute key **`orderType`** (camelCase), but publishers send the message attribute **`order_type`** (snake_case). SNS filter-policy keys are matched **exactly and case-sensitively**, so every priority event is silently filtered out. The standard subscription uses the correct `order_type` key, which is why it works.

## Exact Fix

### Option A — Console

1. SNS → your topic → **Subscriptions** → select the **priority** subscription → **Edit**.
2. Expand **Subscription filter policy**.
3. Change the policy from:
   ```json
   { "orderType": ["priority"] }
   ```
   to:
   ```json
   { "order_type": ["priority"] }
   ```
4. Confirm **Filter policy scope** = **Message attributes**. **Save changes.**

### Option B — AWS CLI

```bash
SUB_ARN=<priority subscription arn>   # aws sns list-subscriptions-by-topic --topic-arn <topic>

aws sns set-subscription-attributes \
  --subscription-arn "$SUB_ARN" \
  --attribute-name FilterPolicy \
  --attribute-value '{"order_type":["priority"]}'

# (Optional, ensure scope is attributes)
aws sns set-subscription-attributes \
  --subscription-arn "$SUB_ARN" \
  --attribute-name FilterPolicyScope \
  --attribute-value MessageAttributes
```

> Permanent fix (solution Terraform): the priority subscription's `filter_policy` uses `order_type`.

## Validation Evidence

```bash
TOPIC=<topic-arn>
PRIORITY_Q=<priority queue url>

aws sns publish --topic-arn "$TOPIC" --message '{"orderId":"rush-1"}' \
  --message-attributes '{"order_type":{"DataType":"String","StringValue":"priority"}}'

aws sqs receive-message --queue-url "$PRIORITY_Q" --wait-time-seconds 5 \
  --max-number-of-messages 1
# -> a Message whose body contains "rush-1"
```

Standard still works:

```bash
aws sns publish --topic-arn "$TOPIC" --message '{"orderId":"std-1"}' \
  --message-attributes '{"order_type":{"DataType":"String","StringValue":"standard"}}'
aws sqs receive-message --queue-url <standard queue url> --wait-time-seconds 5
```

## Common Mistakes

- **Editing the message body instead of the filter policy** — the body was never the problem.
- **Changing the value (`priority`) instead of the key (`order_type`)** — the value already matched.
- **Publishing without message attributes** during testing — then *everything* is filtered out and you misdiagnose.
- **Setting the filter policy on the topic** — filter policies live on the **subscription**, not the topic.

## Distinguish From Similar Failures

| Symptom | Diagnosis |
|---------|-----------|
| Subscriber gets nothing, `NumberOfNotificationsFilteredOut` climbs | Filter-policy mismatch (**this lab**) |
| Subscriber gets nothing, `NumberOfNotificationsFailed` climbs | Delivery failure — usually the SQS queue policy denies `sns.amazonaws.com` |
| Message arrives but body is wrapped in SNS JSON | `raw_message_delivery` off — not a drop, an envelope surprise |
| *Everything* is filtered out | Publisher stopped sending message attributes entirely |

## Key Takeaways / Exam Angle

- **SNS filter policies match message attributes by exact, case-sensitive key.** This is a classic "silent drop" exam scenario.
- **No error + no DLQ + empty subscriber = filter-policy mismatch.** Compare publisher attributes to subscription filter, character by character.
- **Filter policy scope** (MessageAttributes vs MessageBody) determines what SNS inspects.
