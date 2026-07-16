# EM14 — Sealed Credentials: Secrets Manager + KMS — Student Handout

> **Region:** All lab resources are deployed in **US West (Oregon) — `us-west-2`**. Before running any AWS CLI command or opening the console, confirm your region is `us-west-2`. If you are in the wrong region, your resources will not exist and every command will fail.


## Lab Goals

- Understand how Secrets Manager uses **KMS** to encrypt secrets.
- Diagnose an `AccessDenied` that comes from **KMS**, not Secrets Manager.
- Grant the missing `kms:Decrypt`.

## Scenario

**Acme Retail**'s checkout Lambda needs the database password, stored in Secrets Manager and encrypted with a customer-managed KMS key. The Lambda has permission to read the secret — yet every call is **denied**. The credentials are sealed behind a lock the function isn't allowed to open.

## Architecture

```
invoke ─▶ Lambda ──GetSecretValue──▶ Secrets Manager (secret)
                                          │ encrypted with
                                          ▼
                                    KMS customer key  ← Lambda can't Decrypt
```

## Starting Symptom

1. Invoking the Lambda returns a **function error**.
2. The log shows `AccessDeniedException` during `GetSecretValue` mentioning **`kms:Decrypt`** and the KMS key.
3. The role clearly allows `secretsmanager:GetSecretValue` — but the call still fails.

## Time Limit

**30 minutes.**

## Guided Investigation Hints

1. Secrets Manager encrypts secret values with a **KMS key**. To *read* a secret encrypted with a **customer-managed** key, the caller needs **both** `secretsmanager:GetSecretValue` **and** `kms:Decrypt` on that key.
2. Read the error: if it says `kms:Decrypt`, the Secrets Manager permission is fine — the **KMS** permission is missing.
3. You can grant `kms:Decrypt` via the **role's IAM policy** (the key's default policy already lets the account delegate through IAM).
4. Scope `kms:Decrypt` to the **specific key ARN**.

## Debugging Playbook (How a Pro Thinks)

Reading an encrypted secret is a **two-permission operation**, and the error tells you which half is missing:

```
GetSecretValue ──▶ Secrets Manager ──(decrypt data key)──▶ KMS
      needs: secretsmanager:GetSecretValue      needs: kms:Decrypt on the CMK
```

If the denial names `kms:Decrypt`, stop editing Secrets Manager permissions — the gate is KMS. This "the error names the missing action, and the action names the service" habit generalizes everywhere in AWS.

Why you never hit this in dev: the default **AWS-managed key** (`aws/secretsmanager`) auto-grants decryption to same-account principals. **Customer-managed keys make the permission explicit** — that's a feature (auditable, revocable, cross-account-capable), and it's why production secrets use CMKs. Know the dual-control model too: KMS access = key policy **AND** IAM policy agreeing; the default key policy delegates to IAM, which is why an IAM grant suffices here.

## Things to Check

- **CloudWatch Logs:** does the `AccessDeniedException` name `kms:Decrypt`?
- **IAM → the Lambda's role:** does any statement allow `kms:Decrypt` on the key?
- **KMS → your key → ARN**; **Secrets Manager → your secret → Encryption key** (which CMK?).

## Validation Criteria

You are done when:

1. Invoking the Lambda returns the secret's fields (e.g., `{"db":"connected","user":"acme_app"}`) — **no** `AccessDenied`.
2. The log shows a successful `GetSecretValue`.
3. The `kms:Decrypt` grant is scoped to the **specific key ARN**.

## Key Takeaways

- **Reading a customer-key-encrypted secret needs `GetSecretValue` *and* `kms:Decrypt`.** Miss the KMS half and you're denied.
- **The error names the missing action** — `kms:Decrypt` vs `secretsmanager:GetSecretValue` points you to the right service.
- **AWS-managed keys** would have hidden this; **customer-managed keys** make the KMS permission explicit.

## Reflection Questions

1. Why doesn't this happen with the default AWS-managed Secrets Manager key?
2. When would you grant KMS access via the **key policy** instead of the IAM policy?
3. How does `kms:Decrypt` differ from `kms:GenerateDataKey`, and which does read vs. write need?
