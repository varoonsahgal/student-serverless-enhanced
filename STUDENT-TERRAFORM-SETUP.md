# Student Self-Service Terraform — Building Your Own Single-Instance Lab

This guide is for **individual students** who want to stand up a module's broken environment themselves, instead of waiting for an instructor to deploy the shared cohort stack described in [`INSTRUCTOR-SETUP.md`](INSTRUCTOR-SETUP.md).

It does not replace anything. Every module still has its original `terraform/broken/` and `terraform/solution/` stacks, untouched, for instructor-led cohort delivery. This guide covers a new, separate directory that now also exists in every module:

```
EMxx-slug/
├── terraform/               # unchanged — instructor-run, for_each over up to 16 students
│   ├── broken/
│   └── solution/
└── student-terraform/       # new — you run this yourself, builds exactly ONE instance
```

## Before You Start: Read This If You Administer the AWS Account

[`INSTRUCTOR-SETUP.md`](INSTRUCTOR-SETUP.md) §9 says students never run Terraform and only need console read/interact access — that model assumes the instructor applies everything. Self-service mode is the opposite: **the student needs real create permissions** (IAM roles/policies, Lambda, API Gateway, and whatever else the specific module provisions), not just read access. Before handing a student the `student-terraform/` path, either:

- give them their own sandbox AWS account (cleanest), or
- grant them a scoped IAM policy in the shared account broad enough to create that module's resources.

A student with create-IAM-role permissions in a shared account is a materially bigger blast radius than the read-only model `INSTRUCTOR-SETUP.md` assumes elsewhere — don't skip this.

## 1. What's Different in `student-terraform/`

The instructor stack uses `for_each = toset(var.student_ids)` to build isolated resources for up to 16 people from one `terraform apply`. That's the wrong shape for one person self-provisioning — it defaults to creating **16 students' worth of resources** if you forget to override the list, and it carries a documented footgun: re-applying with someone's ID missing from the list destroys their resources.

`student-terraform/` removes all of that. Every `for_each` is gone; every resource is a plain singular resource; the `student_ids` list variable is replaced with one `student_id` **string** variable that has **no default on purpose** — Terraform will refuse to apply until you set it. Same architecture, same planted bug, same resource types as the module's `terraform/broken` stack — just sized for one person instead of a roster.

## 2. Prerequisites

- Terraform `>= 1.6` (run `terraform version` to check).
- AWS CLI v2, configured with credentials that have create permissions for this module's services (see the callout above).
- Region **`us-west-2`** (the default in every `variables.tf`; only change it if your instructor tells you to).
- Know which module you're doing (e.g. `EM10-sns-notifications`) — check [`README.md`](README.md)'s module map if you're not sure.

## 3. Pick Your Unique Identifier

Every resource this stack creates is named `${course_prefix}-${student_id}-emNN-...` and tagged `Student = <student_id>`. You choose `student_id` — pick something only you would plausibly use: your name or initials plus a number works well (e.g. `jsmith42`). It must be **3-20 lowercase letters, digits, or hyphens**; the variable's validation will reject anything else with a clear error message.

Why this matters even outside a shared account: a couple of these modules create resources that must be globally unique across *all* AWS accounts on Earth, not just yours — EM11's S3 artifact bucket is the one to watch. A generic `student_id` like `test` will collide with someone else's bucket somewhere. Make it actually unique to you.

## 4. Apply / Destroy Workflow

```bash
# 1. cd into the module you're doing
cd EM10-sns-notifications/student-terraform

# 2. Download providers (first time only)
terraform init

# 3. Build your instance
terraform apply -var 'student_id=jsmith42'

# 4. Read the outputs you need (endpoints, ARNs, table names, etc.)
terraform output
```

Tear it down when you're done:

```bash
terraform destroy -var 'student_id=jsmith42'
```

**Tip:** typing `-var 'student_id=...'` on every command gets old fast. Save it once to a `terraform.tfvars` file in the same directory (already excluded from git by this repo's `.gitignore`, so it's safe to keep secrets/identifiers there):

```hcl
# terraform.tfvars
student_id = "jsmith42"
```

With that file in place, plain `terraform apply` / `terraform destroy` / `terraform output` pick it up automatically — no `-var` needed.

## 5. Your State Is Yours Alone

The instructor's cohort stack shares one Terraform state across everyone in it via `for_each` — that's what makes the "omit a student, destroy their stuff" footgun possible. `student-terraform/` has no such sharing: there's no list, no `for_each`, and (in the normal case of you running this from your own local clone) your state file lives only on your machine and describes only the resources `terraform apply` just built for your `student_id`. A classmate running their own `student-terraform/` apply, from their own clone, cannot see or affect your state, and you cannot affect theirs — even in the same shared AWS account.

## 6. Now Go Do the Lab

This guide only gets the broken environment stood up. Once `terraform apply` finishes, open that module's **`02-student-handout.md`** and start the actual investigation — symptom, evidence gathering, hints, and validation criteria all live there, not here.

## 7. Cost and Quota Notes for Self-Service

One instance is far cheaper than a 16-student cohort deploy, but it isn't free, and a few modules have quirks worth knowing before you apply:

| Module | What to watch |
|--------|----------------|
| EM04 (WAF) | Each instance is its own WAFv2 Web ACL (~$5/mo + $1/rule/mo). Fine for one person; destroy when done so it doesn't linger. |
| EM09 (VPC) | Each instance is its own VPC. AWS's default quota is **5 VPCs per Region per account**. If you and several classmates all self-provision EM09 in the *same* shared account, you'll collectively hit that cap around the 5th person — same landmine the cohort model has, just approached from a different direction. Coordinate, or use separate accounts. |
| EM11 (CodePipeline) | Creates an S3 bucket (must be globally unique — see §3), a CodeBuild project, and a pipeline. CodeBuild bills per build-minute; S3 storage is pennies. |
| EM14 (Secrets/KMS) | One KMS customer-managed key (~$1/mo) and one Secrets Manager secret (~$0.40/mo) per instance. |

Full per-module cost detail lives in each module's `01-instructor-setup-guide.md`.

## 8. Cleanup

```bash
terraform destroy -var 'student_id=jsmith42'
```

Then double-check the module's `01-instructor-setup-guide.md` for anything Terraform can't fully clean up on its own (e.g., Cognito users you created by hand during EM02/EM04, or an SNS email subscription you confirmed during EM10).

## 9. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Error: Missing required argument` for `student_id` on apply | You didn't pass `-var` or set `terraform.tfvars` | Set it — there's no default, by design (§3). |
| Name-conflict error on apply | Someone (maybe a past run of yours) already created a resource with that exact `student_id` in this account | Pick a different `student_id`, or `terraform destroy` your old one first. |
| `BucketAlreadyExists` (EM11 only) | S3 bucket names are unique across *all* AWS accounts globally, not just yours | Your `student_id` needs to be genuinely unique — add a random suffix. |
| `VpcLimitExceeded` (EM09 only) | Your account already has 5 VPCs in this Region | Destroy an old one, ask for a quota increase, or use a different account — see §7. |
| `terraform destroy` hangs on VPC resources (EM09 only) | Lambda's VPC-attached ENIs take a few minutes to detach after the function is deleted | Wait ~10 minutes and re-run `terraform destroy`. |
| Access denied creating resources | Your AWS credentials don't have create permissions for this module's services | See "Before You Start" above — self-service needs more than the read-only access the instructor-led model assumes. |
