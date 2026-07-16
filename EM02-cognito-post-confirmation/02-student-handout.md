# EM02 — The Silent Welcome: Cognito Post-Confirmation Trigger — Student Handout

> **Region:** All lab resources are deployed in **US West (Oregon) — `us-west-2`**. Before running any AWS CLI command or opening the console, confirm your region is `us-west-2`. If you are in the wrong region, your resources will not exist and every command will fail.


## Lab Goals

- Understand how Amazon **Cognito Lambda triggers** fire during the sign-up lifecycle.
- Diagnose why a **post-confirmation** workflow never runs.
- Prove a trigger is wired using CloudWatch Logs.

## Scenario

At **Acme Retail**, every new customer is supposed to be auto-subscribed to the order-notifications SNS topic the moment they confirm their account. Marketing reports: "Nobody who signed up today is getting our emails." The sign-up itself works — users can log in — but the welcome workflow is dead silent.

## Architecture

```
Customer sign-up ─▶ Cognito User Pool
                        │  (on confirm)
                        ▼
                 [ PostConfirmation trigger ]  ??? ─▶ subscribe Lambda ─▶ SNS topic
```

## Starting Symptom

1. A user signs up and is confirmed successfully.
2. **No** email subscription appears on the SNS topic.
3. The subscribe Lambda's CloudWatch log group has **no new log streams** after a confirmation — as if it was never called.

## Time Limit

**30 minutes.**

## Guided Investigation Hints

1. If a Lambda's log group shows **zero invocations**, the service is not calling it at all. Focus on the *wiring*, not the code.
2. Cognito calls Lambdas only for triggers that are **configured on the user pool**. Look at the user pool's **Lambda triggers** (a.k.a. "User pool properties → Lambda triggers").
3. A trigger also needs **permission**: Cognito must be allowed to invoke the function (a Lambda resource-based policy statement with principal `cognito-idp.amazonaws.com`).
4. Test the flow yourself:
   ```bash
   aws cognito-idp sign-up --client-id <client> --username test1@acme.example \
     --password 'Passw0rd!23' --user-attributes Name=email,Value=test1@acme.example
   aws cognito-idp admin-confirm-sign-up --user-pool-id <pool> --username test1@acme.example
   ```
   Then check the Lambda's logs and the SNS subscriptions.

## Debugging Playbook (How a Pro Thinks)

The most important split in serverless debugging:

```
Does the function's log group have ANY new streams?
├── NO  → the service never invoked it → WIRING problem
│         (trigger not configured, or missing invoke permission)
└── YES → it ran and failed → CODE or IAM problem
          (read the traceback / AccessDenied)
```

A Cognito trigger is a **two-key lock**: (1) the trigger selected on the user pool, and (2) a resource-based policy letting `cognito-idp.amazonaws.com` invoke the function. The console adds key 2 automatically when you attach via the UI; CLI/IaC wiring must add it explicitly — which is why "it works when clicked but not when scripted" is such a common story. Verify wiring with `aws cognito-idp describe-user-pool --query 'UserPool.LambdaConfig'` and `aws lambda get-policy`.

## Things to Check

- **Cognito → your user pool → User pool properties → Lambda triggers:** is a **Post confirmation** trigger set?
- **Lambda → your subscribe function → Configuration → Permissions → Resource-based policy:** is Cognito allowed to invoke it?
- **CloudWatch Logs:** any streams at all after a confirm?
- **SNS → your topic → Subscriptions:** anything pending?

## Validation Criteria

You are done when:

1. Confirming a new user produces a **new CloudWatch log stream** for the subscribe Lambda.
2. A **`Pending confirmation`** email subscription appears on the SNS topic for that user's email.
3. Repeating the sign-up/confirm flow reliably creates one subscription per user.

## Key Takeaways

- **No logs at all = not invoked.** A silent Lambda is a wiring problem, not a code problem.
- **A Cognito trigger is two things:** (1) the trigger configured on the user pool, and (2) a resource-based permission letting Cognito invoke the function. Miss either and nothing happens.
- **Post-confirmation** fires after a user confirms (including admin confirm) — the right hook for "do X once, on account creation."

## Reflection Questions

1. How would you tell a *wiring* problem (no logs) apart from a *code/permissions* problem (logs with an error)?
2. Why does a Lambda trigger need a resource-based policy in addition to being selected in the console?
3. If post-confirmation fails, should account creation fail too? What does Cognito actually do?
