# EM02 — The Silent Welcome — Solution Handout

> Instructor answer key.

## Original Symptom

New users confirm successfully, but the subscribe Lambda is never invoked (no log streams) and no SNS subscription is created.

## Root Cause

The Cognito user pool has **no Post-Confirmation trigger configured**, and the subscribe Lambda has **no resource-based permission** allowing Cognito to invoke it. Both are required; the broken stack omits both. The Lambda code and its `sns:Subscribe` IAM permission are correct — the function is simply never called.

### Why it happened

The function was deployed and its execution role was set up, but the final wiring step (attaching it as the user pool's `PostConfirmation` trigger and granting Cognito `lambda:InvokeFunction`) was never done.

## Exact Fix

### Option A — Console

1. **Add the trigger:**
   - Cognito → your user pool → **User pool properties → Lambda triggers → Add Lambda trigger**.
   - Trigger type: **Sign-up → Post confirmation trigger**.
   - Select the subscribe Lambda → **Save changes**.
   - The console automatically adds the invoke permission when you attach the trigger this way.
2. If you wire it via API/CLI instead, also add the invoke permission (below).

### Option B — AWS CLI

```bash
POOL=<user-pool-id>
FN_ARN=<subscribe lambda arn>
FN_NAME=<subscribe lambda name>

# 1. Grant Cognito permission to invoke the function
aws lambda add-permission \
  --function-name "$FN_NAME" \
  --statement-id AllowCognitoInvoke \
  --action lambda:InvokeFunction \
  --principal cognito-idp.amazonaws.com \
  --source-arn "arn:aws:cognito-idp:<region>:<account>:userpool/$POOL"

# 2. Attach the PostConfirmation trigger
aws cognito-idp update-user-pool \
  --user-pool-id "$POOL" \
  --lambda-config PostConfirmation="$FN_ARN"
```

> Note: `update-user-pool` replaces the whole config for some fields — if your pool has other settings, include them or manage this in Terraform (the permanent fix). The **solution Terraform** sets `lambda_config { post_confirmation = ... }` on the pool and adds an `aws_lambda_permission` with principal `cognito-idp.amazonaws.com`.

## Validation Evidence

```bash
aws cognito-idp sign-up --client-id <client> --username test2@acme.example \
  --password 'Passw0rd!23' --user-attributes Name=email,Value=test2@acme.example
aws cognito-idp admin-confirm-sign-up --user-pool-id <pool> --username test2@acme.example

# New log stream appears:
aws logs describe-log-streams --log-group-name /aws/lambda/<subscribe-fn> \
  --order-by LastEventTime --descending --max-items 1

# Subscription now pending:
aws sns list-subscriptions-by-topic --topic-arn <topic-arn>
# ... "SubscriptionArn": "PendingConfirmation", "Endpoint": "test2@acme.example"
```

## Common Mistakes

- **Selecting the trigger but not saving**, or picking **Pre**-signup instead of **Post**-confirmation.
- **Wiring via CLI but forgetting `add-permission`** → Cognito logs an invoke error and the trigger silently no-ops.
- Expecting the subscription to be `Confirmed` immediately — email subscriptions start `Pending confirmation` until the user clicks the link. That's correct behavior.

## Distinguish From Similar Failures

| Symptom | Diagnosis |
|---------|-----------|
| No log streams at all after confirm | Trigger not wired or missing invoke permission (**this lab**) |
| Log streams exist, traceback inside | Trigger fine; the function code or its IAM is broken |
| Subscription created but stuck `Pending confirmation` | Working as designed — the user hasn't clicked the email link |
| Sign-up itself fails | Pre-sign-up trigger or pool policy problem, not post-confirmation |

## Key Takeaways / Exam Angle

- **Cognito Lambda triggers = config + invoke permission.** The exam loves the "trigger selected but no permission" (or vice-versa) trap.
- **Post-confirmation** is the canonical place for "run once when an account becomes active."
- **A silent Lambda (no logs) is always a wiring/permission issue**, never a code bug.
