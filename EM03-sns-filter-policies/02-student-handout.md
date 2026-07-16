# EM03 — Lost in the Fan-Out: SNS Filter Policies — Student Handout

> **Region:** All lab resources are deployed in **US West (Oregon) — `us-west-2`**. Before running any AWS CLI command or opening the console, confirm your region is `us-west-2`. If you are in the wrong region, your resources will not exist and every command will fail.


## Lab Goals

- Understand how Amazon **SNS subscription filter policies** route messages by **message attributes**.
- Diagnose a "silent drop" where a subscriber receives nothing.
- Prove delivery using SQS queue depth.

## Scenario

**Acme Retail** routes order-status events through one SNS topic that fans out to two teams:

- a **priority** fulfillment queue (rush orders), and
- a **standard** fulfillment queue (everything else).

Ops reports: "Standard orders are flowing, but the priority team's queue is bone dry — even during the rush." No errors anywhere. Messages just vanish.

## Architecture

```
aws sns publish (attribute order_type = priority|standard)
        │
        ▼
   SNS topic  ──[filter: standard]──▶ SQS standard   ✅ receiving
        └──────[filter: priority]──▶ SQS priority    ❌ empty
```

## Starting Symptom

1. Publishing an event with message attribute `order_type = standard` → the **standard** SQS queue receives it.
2. Publishing with `order_type = priority` → the **priority** SQS queue stays at **0 messages**.
3. No delivery failures in SNS metrics — the messages are being **filtered out**, not failing.

## Time Limit

**25 minutes.**

## Guided Investigation Hints

1. SNS filter policies match against **message attributes**, not the message body. A mismatch is a *silent* drop — no error, no DLQ.
2. Compare **exactly** what attribute name the publisher sends vs. what the subscription's filter policy expects. Attribute names are **case-sensitive** and must match character-for-character.
3. Also confirm the subscription's **filter policy scope** is `MessageAttributes` (the default), not `MessageBody`.
4. Test each subscriber independently:
   ```bash
   aws sns publish --topic-arn <topic> --message '{"orderId":"o1"}' \
     --message-attributes '{"order_type":{"DataType":"String","StringValue":"priority"}}'
   aws sqs receive-message --queue-url <priority-queue-url> --wait-time-seconds 5
   ```

## Debugging Playbook (How a Pro Thinks)

A **silent drop** is the hardest class of failure: no error, no retry, no DLQ. Attack it by comparing the two sides of the contract:

1. **What the publisher sends:** capture the exact `--message-attributes` JSON (names are case-sensitive).
2. **What the subscription expects:** `aws sns get-subscription-attributes --query 'Attributes.FilterPolicy'`.
3. Diff them **character by character** — `orderType` vs `order_type` is invisible at a glance.
4. Confirm `FilterPolicyScope` matches where the data actually is (`MessageAttributes` vs `MessageBody`).

Pro shortcut: the topic's CloudWatch metric **`NumberOfNotificationsFilteredOut`** turns a silent drop into a visible counter. If it climbs when you publish, the message arrived and was *deliberately* filtered — you've localized the bug to the filter policy without reading a single log line.

## Things to Check

- **SNS → your topic → Subscriptions →** each subscription's **Subscription filter policy**.
- The **exact attribute key** in each filter policy vs. the key you publish.
- **Filter policy scope** on each subscription.
- **SQS → priority queue → Monitoring → ApproximateNumberOfMessagesVisible.**

## Validation Criteria

You are done when:

1. `order_type = priority` publish → message appears in the **priority** queue.
2. `order_type = standard` publish → message appears in the **standard** queue (still works).
3. Neither queue receives the other's messages (cross-talk stays filtered out).

## Key Takeaways

- **SNS filters match message attributes, and attribute names are case-sensitive.** One wrong character = silent drop.
- **A "silent drop" has no error and no DLQ.** Diagnose it by comparing publisher attributes to the subscription's filter policy.
- **Filter policy scope** decides whether SNS looks at attributes or the body — know which one you set.

## Reflection Questions

1. Why does SNS filter on attributes rather than the message body by default?
2. What CloudWatch metric would help you notice that a subscription is dropping most messages?
3. How would you design attribute names to avoid case/spelling mismatches across teams?
