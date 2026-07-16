# EM14 — Sealed Credentials — Solution Handout

> Instructor answer key.

## Original Symptom

`GetSecretValue` fails with `AccessDeniedException` naming `kms:Decrypt` on the customer key, even though the role allows `secretsmanager:GetSecretValue`.

## Root Cause

The secret is encrypted with a **customer-managed KMS key**. Reading it requires `kms:Decrypt` on that key **in addition to** `secretsmanager:GetSecretValue`. The Lambda's role has the Secrets Manager permission but **not** `kms:Decrypt`, so KMS refuses to decrypt and Secrets Manager surfaces the denial.

## Exact Fix

Grant `kms:Decrypt` on the key ARN to the Lambda's role. (The key's default policy already allows the account to delegate access via IAM, so an IAM grant is sufficient.)

### Console

1. IAM → the Lambda's role → **Add permissions → Create inline policy** → JSON:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": "kms:Decrypt",
       "Resource": "arn:aws:kms:<region>:<account>:key/<key-id>"
     }]
   }
   ```
2. Save.

### CLI

```bash
ROLE=<lambda role name>
KEY_ARN=<cmk arn>

aws iam put-role-policy --role-name "$ROLE" --policy-name allow-kms-decrypt \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"kms:Decrypt\",\"Resource\":\"$KEY_ARN\"}]}"
```

> Permanent fix (solution Terraform): the role's policy adds `kms:Decrypt` on `aws_kms_key.secret[each.key].arn`.

## Validation Evidence

```bash
FN=<fn>
aws lambda invoke --function-name "$FN" /tmp/o.json >/dev/null && cat /tmp/o.json
# {"db":"connected","user":"acme_app"}
```

No `AccessDeniedException` / `kms:Decrypt` in the logs.

## Common Mistakes

- **Adding more Secrets Manager permissions** — the block was KMS, not Secrets Manager.
- **Granting `kms:*` on `*`** — over-broad; scope to the key ARN and the `Decrypt` action.
- **Editing the key policy unnecessarily** — the default key policy already lets IAM delegate; an IAM grant is enough here.
- **Confusing `kms:Decrypt` (read) with `kms:GenerateDataKey` (write/encrypt)** — reading a secret needs `Decrypt`.

## Distinguish From Similar Failures

| Symptom | Diagnosis |
|---------|-----------|
| Denial naming `kms:Decrypt` | Role lacks the KMS half (**this lab**) |
| Denial naming `secretsmanager:GetSecretValue` | Role lacks the Secrets Manager half |
| `ResourceNotFoundException` | Wrong secret ARN/name, or secret deleted (or still in recovery window) |
| Works with default key, breaks after switching to a CMK | The defining CMK fingerprint — the AWS-managed key auto-granted decrypt; the CMK doesn't |
| IAM allows `kms:Decrypt` but still denied | Restrictive **key policy** — both policies must agree |

## Key Takeaways / Exam Angle

- **Customer-managed KMS keys make the `kms:Decrypt` requirement explicit** for reading encrypted secrets — a favorite exam scenario.
- **Read the denied action** to know which service to fix (`kms:Decrypt` vs `secretsmanager:GetSecretValue`).
- **IAM grant vs. key policy:** with the default key policy, an IAM `kms:Decrypt` grant suffices; cross-account or restrictive key policies may require a key-policy grant too.
