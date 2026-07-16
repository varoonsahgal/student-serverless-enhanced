# EM08 — Dead Letters — Solution Handout

> Instructor answer key.

## Original Symptom

A poison message (`{"poison": true}`) is retried endlessly; there is no DLQ; the main queue never drains it.

## Root Cause

The `order-errors` SQS queue has **no redrive policy** and there is **no dead-letter queue**. When the consumer Lambda throws on the poison message, SQS returns it after the visibility timeout and re-delivers it indefinitely. Nothing bounds the retries or quarantines the bad message.

## Exact Fix

Create a DLQ and attach a redrive policy to the source queue (`maxReceiveCount = 3`).

### Console

1. SQS → **Create queue** → name `...-em08-order-errors-dlq` (standard). Create.
2. SQS → your `order-errors` queue → **Edit** → **Dead-letter queue** → **Enabled** → choose the DLQ → **Maximum receives** = `3` → **Save**.

### CLI

```bash
MAIN_URL=<main queue url>
DLQ_ARN=<dlq arn>   # aws sqs get-queue-attributes --queue-url <dlq> --attribute-names QueueArn

aws sqs set-queue-attributes --queue-url "$MAIN_URL" --attributes \
  "RedrivePolicy={\"deadLetterTargetArn\":\"$DLQ_ARN\",\"maxReceiveCount\":\"3\"}"
```

> Permanent fix (solution Terraform): a `aws_sqs_queue.dlq` exists and the main queue sets `redrive_policy` with `maxReceiveCount = 3`.

## Validation Evidence

```bash
MAIN=<main queue url>; DLQ=<dlq url>

# poison message -> after 3 receives, lands in the DLQ
aws sqs send-message --queue-url "$MAIN" --message-body '{"poison": true}'
sleep 60   # 3 receives * visibility timeout
aws sqs get-queue-attributes --queue-url "$DLQ"  --attribute-names ApproximateNumberOfMessages   # 1
aws sqs get-queue-attributes --queue-url "$MAIN" --attribute-names ApproximateNumberOfMessages   # 0

# normal message still processes and does NOT hit the DLQ
aws sqs send-message --queue-url "$MAIN" --message-body '{"orderId":"o-ok"}'
```

CloudWatch shows the poison message failing exactly 3 times, then no more.

## Common Mistakes

- **Setting `maxReceiveCount` on the DLQ instead of the source queue** — the redrive policy belongs on the **source** queue.
- **DLQ visibility/retention too short** — messages can age out of the DLQ before you inspect them; give the DLQ generous retention.
- **Source visibility timeout shorter than the Lambda timeout** — causes duplicate deliveries and miscounts; keep visibility ≥ processing time.
- **"Fixing" by deleting the poison message** — that hides the class of problem; the DLQ is the correct sink.

## Distinguish From Similar Failures

| Symptom | Diagnosis |
|---------|-----------|
| Same message re-delivered, `ApproximateReceiveCount` climbing, consumer throws | Poison message + no redrive policy (**this lab**) |
| Duplicate deliveries while consumer is *still processing* | Visibility timeout shorter than processing time |
| Messages vanish without processing | Retention expired, or a *second* consumer is draining the queue |
| Everything (good and bad) lands in the DLQ | `maxReceiveCount` too low, or the consumer fails on all input |

## Key Takeaways / Exam Angle

- **Redrive policy (`deadLetterTargetArn` + `maxReceiveCount`) on the source queue bounds retries and quarantines poison messages.** Core SQS exam concept.
- **DLQs are diagnostic** — inspect and redrive, don't just drop.
- **Visibility timeout ≥ processing time** prevents duplicate processing.
