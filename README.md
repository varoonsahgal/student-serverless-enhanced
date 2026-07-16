# Acme Retail Serverless Recovery Challenge — Enhanced Break-Fix Labs

A **15-module, break-fix lab track** that mirrors the hands-on AWS **Serverless Microcredential** assessment. Every module drops you into a broken piece of the **Acme Retail** serverless ecommerce platform and asks you to restore it under time pressure.

> Broken system → observable symptom → investigation → evidence → hypothesis → fix → validation → debrief


## The Story (used across all 15 labs)

> **Acme Retail** runs a serverless ecommerce platform on AWS. The lead engineer left abruptly. A flash sale starts soon. Customers must be able to sign up, browse products, keep a cart, check out, and get order notifications — end to end. Something in each subsystem is broken. Your job: find it, prove it, fix it, and prove it's fixed.


### Suggested groupings

- **API & Auth day:** EM01, EM02, EM03, EM04.
- **Data & Workflow day:** EM05, EM06, EM07, EM08.
- **Ops & Security day:** EM09, EM10, EM12, EM13, EM14.
- **CI/CD + Capstone:** EM11, EM15.

Every lab stands alone; drop any of them without breaking the others.

## Per-Module Deliverable Contract

Every module folder contains **exactly four files**:

1. `01-instructor-setup-guide.md` — prerequisites, apply, prove-it's-broken, reset, cleanup, cost.
2. `02-student-handout.md` — goals, scenario, ASCII architecture, symptom, hints, validation, **key takeaways**, reflection. **No answers.**
3. `03-student-solution-handout.md` — root cause, exact fix (console + CLI), validation evidence, common mistakes, **key takeaways / exam angle**.
4. `04-instructor-terraform.md` — the annotated reference for the **broken** and **solution** Terraform stacks, plus apply/destroy commands.

plus a **`terraform/`** directory containing the runnable code itself:

- `terraform/broken/` — full HCL + Lambda source; deploy this for students.
- `terraform/solution/` — full HCL + Lambda source; the instructor answer key (separate state, separate `course_prefix`).

Both stacks are parameterized for up to 16 students per cohort (2 cohorts, run one at a time) in one account. Before class, run the single validation runbook: [`PRECLASS-VALIDATION.md`](PRECLASS-VALIDATION.md).

## Running This For up to 16 Students per Cohort

Read [`INSTRUCTOR-SETUP.md`](INSTRUCTOR-SETUP.md) first. Highlights:

- Every stack uses `for_each = toset(var.student_ids)` so **one `terraform apply` builds isolated resources for the whole cohort** (default 16 students — the max per cohort; the two cohorts run one at a time, so 16 replicas is all you ever need).
- Every resource name is `${var.course_prefix}-${each.key}-emNN-...` and tagged `Student = each.key`.
- Deploy one broken stack per lab you plan to teach; hand each student their `student_id` prefix.
- Destroy per-student or whole-cohort with a single command.

## Global Prerequisites

- AWS account with admin or `PowerUserAccess` for the instructor.
- **Region: `us-west-2`** (all defaults, CLI examples, and provider config target it; no Bedrock here so any commercial region works if you change `var.region`).
- Terraform `>= 1.6`, AWS provider `>= 5.60`, `archive` provider `>= 2.4`.
- AWS CLI v2.
- An AWS Budget alert (suggest $50/month) before you start.

## Cost Summary

Almost everything here is **$0 idle** (Lambda, API Gateway, DynamoDB on-demand, Step Functions Standard, SQS, SNS, Cognito, CloudWatch at 7-day retention). Watch these:

| Module | Non-zero idle cost |
|--------|--------------------|
| EM04 | WAFv2 web ACL: ~$5/mo per ACL + $1/rule/mo. **One shared ACL per cohort is fine; per-student ACLs add up.** |
| EM11 | CodePipeline: ~$1/active pipeline/mo; CodeBuild billed per build-minute; S3 artifact storage pennies. |
| EM14 | KMS CMK ~$1/mo each; Secrets Manager secret ~$0.40/mo each. |
| EM09 | Uses **VPC Gateway endpoints (free)** in the solution — no NAT Gateway, so ~$0. |

> Pricing shown is an illustrative example. Verify current pricing for your Region before delivery. **Always run cleanup at end of day** (see each module's `01-` guide and [`_helpers/destroy-all-notes.md`](_helpers/destroy-all-notes.md)).

## Legacy / Do Not Edit

The original monolithic challenge brief lives at `../../foundational-stuff.md` and is the design source for these labs. The archived combined course is under `../_legacy/`. Do not edit legacy content.
