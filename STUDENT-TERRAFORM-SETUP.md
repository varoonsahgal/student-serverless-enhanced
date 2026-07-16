# Student Self-Service Terraform — Building Your Own Single-Instance Lab

This guide is for **individual students** who want to stand up a module's broken environment themselves, instead of waiting for an instructor to deploy the shared cohort stack described in [`INSTRUCTOR-SETUP.md`](INSTRUCTOR-SETUP.md).

It does not replace anything. Every module still has its original `terraform/broken/` and `terraform/solution/` stacks, untouched, for instructor-led cohort delivery. This guide covers a new, separate path.

```
EMxx-slug/
├── terraform/               # unchanged — instructor-run, for_each over up to 16 students
│   ├── broken/
│   └── solution/
└── student-terraform/       # new — you run this yourself, builds exactly ONE instance
```

## Before You Start: Read This If You Administer the AWS Account

[`INSTRUCTOR-SETUP.md`](INSTRUCTOR-SETUP.md) §9 says students never run Terraform and only need console read/interact access — that model assumes the instructor applies everything. Self-service changes the threat model. Before letting a student self-provision, you must either:

- give them their own sandbox AWS account (cleanest), or
- grant them a scoped IAM policy in the shared account broad enough to create that module's resources.

A student with create-IAM-role permissions in a shared account is a materially bigger blast radius than the read-only model `INSTRUCTOR-SETUP.md` assumes elsewhere — don't skip this.

## 1. What's Different in `student-terraform/`

The instructor stack uses `for_each = toset(var.student_ids)` to build isolated resources for up to 16 people from one `terraform apply`. That's the wrong shape for one person self-provisioning — it requires you to know all student IDs up front and makes partial destroys risky.

`student-terraform/` removes all of that. Every `for_each` is gone; every resource is a plain singular resource; the `student_ids` list variable is replaced with one `student_id` **string** variable that you supply yourself.

## 2. Prerequisites

- Terraform `>= 1.6` — see **§2a** below for install instructions.
- AWS CLI v2, configured with credentials that have create permissions for this module's services — see **§2b** below for setup instructions.
- Region **`us-west-2`** (the default in every `variables.tf`; only change it if your instructor tells you to).
- Know which module you're doing (e.g. `EM10-sns-notifications`) — check [`README.md`](README.md)'s module map if you're not sure.

### 2a. Installing Terraform

**macOS (Homebrew — recommended):**

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform version   # should print >= 1.6
```

**macOS / Linux (manual):**

1. Go to <https://developer.hashicorp.com/terraform/install> and download the zip for your OS/arch.
2. Unzip and move the binary to somewhere on your `PATH`:
   ```bash
   unzip terraform_*.zip
   sudo mv terraform /usr/local/bin/
   terraform version
   ```

**Windows:**

```powershell
# Option A — winget
winget install HashiCorp.Terraform

# Option B — Chocolatey
choco install terraform
```

Or download the `.zip` from <https://developer.hashicorp.com/terraform/install>, extract `terraform.exe`, and add the folder to your `PATH` via *System Properties → Environment Variables*.

Verify in a new terminal:

```powershell
terraform version
```

### 2b. Installing and Configuring the AWS CLI

**Install AWS CLI v2:**

| Platform | Command / method |
|----------|-----------------|
| macOS (Homebrew) | `brew install awscli` |
| macOS (pkg installer) | Download from <https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html> |
| Linux | `curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip awscliv2.zip && sudo ./aws/install` |
| Windows | Download the MSI from the link above and run it |

Verify:

```bash
aws --version   # should print aws-cli/2.x.x ...
```

**Configure your credentials:**

Run the interactive wizard:

```bash
aws configure
```

You will be prompted for four values:

```
AWS Access Key ID [None]:       <paste your Access Key ID>
AWS Secret Access Key [None]:   <paste your Secret Access Key>
Default region name [None]:     us-west-2
Default output format [None]:   json
```

Your instructor will provide the Access Key ID and Secret Access Key. If you are using a personal sandbox account, generate them in the IAM console under *Security credentials → Access keys*.

**Verify the credentials work:**

```bash
aws sts get-caller-identity
```

A successful response looks like:

```json
{
    "UserId": "AIDA...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/jsmith42"
}
```

If you get an `InvalidClientTokenId` or `AuthFailure` error, double-check that you pasted the keys correctly and that the IAM user has the permissions needed for this module.

> **SSO / IAM Identity Center users:** If your organisation uses AWS SSO, run `aws configure sso` instead and follow the prompts. After logging in, export the profile name and prefix all `aws` and `terraform` commands with `AWS_PROFILE=<profile-name>`, or add `profile = "<profile-name>"` to the provider block in `variables.tf`.

## 3. Pick Your Unique Identifier

Every resource this stack creates is named `${course_prefix}-${student_id}-emNN-...` and tagged `Student = <student_id>`. You choose `student_id` — pick something only you would plausibly use: your first initial + last name + a number works well (e.g. `jsmith42`). All lowercase, no spaces, keep it under 12 characters.

Why this matters even outside a shared account: a couple of these modules create resources that must be globally unique across *all* AWS accounts on Earth, not just yours — EM11's S3 artifact bucket is the main one. If your `student_id` is too generic (`test`, `student1`) you may collide with someone else's old bucket. Be specific.

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

**Tip:** typing `-var 'student_id=...'` on every command gets old fast. Save it once to a `terraform.tfvars` file in the same directory (already excluded from git by this repo's `.gitignore`, so it won't be committed):

```hcl
# terraform.tfvars
student_id = "jsmith42"
```

With that file in place, plain `terraform apply` / `terraform destroy` / `terraform output` pick it up automatically — no `-var` needed.

## 5. Your State Is Yours Alone

The instructor's cohort stack shares one Terraform state across everyone in it via `for_each` — that's what makes the "omit a student, destroy their stuff" footgun possible. `student-terraform/` has no remote backend configured; state lives in `terraform.tfstate` right next to your `.tf` files. Don't delete it until after you've run `terraform destroy`.

## 6. Now Go Do the Lab

This guide only gets the broken environment stood up. Once `terraform apply` finishes, open that module's **`02-student-handout.md`** and start the actual investigation — symptom, evidence gathering, fix, validation.

## 7. Cost and Quota Notes for Self-Service

One instance is far cheaper than a 16-student cohort deploy, but it isn't free, and a few modules have quirks worth knowing before you apply:

| Module | What to watch |
|--------|----------------|
| EM04 (WAF) | Each instance is its own WAFv2 Web ACL (~$5/mo + $1/rule/mo). Fine for one person; destroy when done so it doesn't linger. |
| EM09 (VPC) | Each instance is its own VPC. AWS's default quota is **5 VPCs per Region per account**. If you and several classmates all self-provision EM09 in the *same* shared account, you'll collectively hit the limit fast. |
| EM11 (CodePipeline) | Creates an S3 bucket (must be globally unique — see §3), a CodeBuild project, and a pipeline. CodeBuild bills per build-minute; S3 storage is pennies. |
| EM14 (Secrets/KMS) | One KMS customer-managed key (~$1/mo) and one Secrets Manager secret (~$0.40/mo) per instance. |

Full per-module cost detail lives in each module's `01-instructor-setup-guide.md`.

## 8. Cleanup

```bash
terraform destroy -var 'student_id=jsmith42'
```

Then double-check the module's `01-instructor-setup-guide.md` for anything Terraform can't fully clean up on its own (e.g., Cognito users you created by hand during EM02/EM04, or an SNS email subscription you confirmed manually).

## 9. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Error: Missing required argument` for `student_id` on apply | You didn't pass `-var` or set `terraform.tfvars` | Set it — there's no default, by design (§3). |
| Name-conflict error on apply | Someone (maybe a past run of yours) already created a resource with that exact `student_id` in this account | Pick a different `student_id`, or `terraform destroy` your previous run first. |
| `BucketAlreadyExists` (EM11 only) | S3 bucket names are unique across *all* AWS accounts globally, not just yours | Your `student_id` needs to be genuinely unique — add a random suffix. |
| `VpcLimitExceeded` (EM09 only) | Your account already has 5 VPCs in this Region | Destroy an old one, ask for a quota increase, or use a different account — see §7. |
| `terraform destroy` hangs on VPC resources (EM09 only) | Lambda's VPC-attached ENIs take a few minutes to detach after the function is deleted | Wait ~10 minutes and re-run `terraform destroy`. |
| Access denied creating resources | Your AWS credentials don't have create permissions for this module's services | See "Before You Start" above — self-service needs more than the read-only access the console-only model uses. |
| `InvalidClientTokenId` or `AuthFailure` on any AWS call | Credentials are wrong, expired, or not configured for `us-west-2` | Re-run `aws configure` and verify with `aws sts get-caller-identity` (§2b). |
