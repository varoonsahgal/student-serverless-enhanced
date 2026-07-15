# Acme Retail Serverless Recovery Challenge — Enhanced Break-Fix Labs

A **15-module, break-fix lab track** that mirrors the hands-on AWS **Serverless Microcredential** assessment. Every module drops you into a broken piece of the **Acme Retail** serverless ecommerce platform and asks you to restore it under time pressure.

> Broken system → observable symptom → investigation → evidence → hypothesis → fix → validation → debrief

These labs are a companion to the two 2-day bootcamp classes under [`../serverless/`](../serverless/README.md) and [`../agentic-ai/`](../agentic-ai/README.md). They are **enhanced** in three ways:

1. **One recurring story.** Every lab is a scene from the same incident: Acme Retail's lead engineer quit two hours before a major sale, and the platform is on fire.
2. **Exam-shaped faults.** Each fault is the kind of misconfiguration the microcredential assessment plants: a missing IAM action, a wrong payload format version, a key-schema mismatch, a filter-policy typo, a VPC with no route to a service.
3. **Fully independent.** No lab depends on any other lab's state. You can teach 3 of them or all 15, in any order.

## The Story (used across all 15 labs)

> **Acme Retail** runs a serverless ecommerce platform on AWS. The lead engineer left abruptly. A flash sale starts soon. Customers must be able to sign up, browse products, keep a cart, check out, and get order notifications — end to end. Something in each subsystem is broken. Your job: find it, prove it, fix it, and prove it's fixed.

## Module Map

| # | Module | AWS Focus | The Break (one-line) |
|---|--------|-----------|----------------------|
| EM01 | [Checkout 404 — API Gateway Routing Blackout](EM01-api-gateway-checkout/) | API Gateway (HTTP API), Lambda proxy | Payload format v1 vs v2 + a missing route |
| EM02 | [The Silent Welcome — Cognito Post-Confirmation](EM02-cognito-post-confirmation/) | Cognito, Lambda triggers, SNS | Post-confirmation trigger never wired |
| EM03 | [Lost in the Fan-Out — SNS Filter Policies](EM03-sns-filter-policies/) | SNS, message attributes, SQS | Subscription filter-policy key mismatch |
| EM04 | [The Locked Front Door — Authorizer + WAF](EM04-authorizer-waf/) | API Gateway (REST), Cognito authorizer, WAF | Wrong token source + WAF default BLOCK |
| EM05 | [The Vanishing Cart — DynamoDB Persistence](EM05-dynamodb-cart/) | DynamoDB, Lambda | Key attribute name mismatch (schema vs code) |
| EM06 | [Orders Into the Void — Step Functions Start](EM06-stepfunctions-start/) | Step Functions, Lambda, IAM | Lambda role missing `states:StartExecution` |
| EM07 | [The Broken Assembly Line — SFN Error Handling](EM07-stepfunctions-catch/) | Step Functions, ASL Retry/Catch | Task state has no `Catch`, execution FAILs |
| EM08 | [Dead Letters — SQS DLQ & Poison Messages](EM08-sqs-dlq/) | SQS, Lambda, DLQ | Queue has no redrive policy (no DLQ) |
| EM09 | [Lambda in the Network Cage — VPC](EM09-vpc-lambda/) | VPC, Lambda, DynamoDB, VPC endpoints | Private subnet, no route to DynamoDB |
| EM10 | [Silent Receipts — SNS Order Notifications](EM10-sns-notifications/) | SNS, Lambda, env config | `TOPIC_ARN` env var points to wrong topic |
| EM11 | [The Pipeline That Wouldn't Deploy — CI/CD](EM11-codepipeline/) | CodePipeline, CodeBuild, IAM | Build role missing `lambda:UpdateFunctionCode` |
| EM12 | [Flying Blind — CloudWatch Observability](EM12-observability/) | CloudWatch Logs, Lambda, IAM | Role lacks `logs:*`; real bug hidden beneath |
| EM13 | [The Access-Denied Maze — IAM Least Privilege](EM13-iam-least-privilege/) | IAM, DynamoDB, Lambda | Policy Resource ARN scoped to wrong table |
| EM14 | [Sealed Credentials — Secrets Manager + KMS](EM14-secrets-kms/) | Secrets Manager, KMS, Lambda | Role can read secret but can't `kms:Decrypt` |
| EM15 | [Black Friday Capstone — Multi-Fault Recovery](EM15-black-friday-capstone/) | API GW + Lambda + DDB + SFN + SNS | Four independent planted faults |

### Suggested groupings

- **API & Auth day:** EM01, EM02, EM03, EM04.
- **Data & Workflow day:** EM05, EM06, EM07, EM08.
- **Ops & Security day:** EM09, EM10, EM12, EM13, EM14.
- **CI/CD + Capstone:** EM11, EM15.

Every lab stands alone; drop any of them without breaking the others.

