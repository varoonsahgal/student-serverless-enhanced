# EM04 — The Locked Front Door — Solution Handout

> Instructor answer key.

## Original Symptom

Valid tokens return `401`; requests are also `403`-blocked by WAF; the backend Lambda is never invoked.

## Root Causes (two planted faults)

| # | Fault | Where | Effect |
|---|-------|-------|--------|
| 1 | Authorizer `identity_source = "method.request.header.Auth"` | Cognito authorizer | Client sends `Authorization`; authorizer reads a header that isn't there → `401` |
| 2 | WAF web ACL `default_action = Block` with no allow rule | WAFv2 web ACL | Every request blocked → `403` before the API |

### Why it happened

The authorizer was pointed at a header named `Auth` instead of the standard `Authorization`. Separately, the WAF was created with a **block-by-default** posture and only reputation rules — but no rule that allows normal traffic — so the default `Block` denies everyone.

## Exact Fix

### Fault 1 — Authorizer identity source

**Console:** API Gateway → your REST API → **Authorizers** → your Cognito authorizer → **Edit** → **Token source** = `Authorization` → **Save**. Then **Resources → GET /orders → Method Request** → confirm the authorizer is selected → **Deploy API** to `prod`.

**CLI:**
```bash
API_ID=<rest-api-id>
AUTH_ID=<authorizer-id>   # aws apigateway get-authorizers --rest-api-id $API_ID
aws apigateway update-authorizer --rest-api-id "$API_ID" --authorizer-id "$AUTH_ID" \
  --patch-operations op=replace,path=/identitySource,value=method.request.header.Authorization
aws apigateway create-deployment --rest-api-id "$API_ID" --stage-name prod
```

### Fault 2 — WAF default action

**Console:** WAF & Shield → **Web ACLs** → your ACL → **Rules** tab → **Default web ACL action for requests that don't match any rules** → set to **Allow** → **Save**. Keep the Amazon IP Reputation and Anonymous IP managed rule groups (they *block* bad traffic while default `Allow` passes the rest).

**CLI (conceptual):** `aws wafv2 update-web-acl` requires the full ACL definition and a lock token; the durable fix is the solution Terraform, which sets `default_action { allow {} }` and keeps the two managed rule groups with `override_action { none {} }`.

> Permanent fix (solution Terraform): `identity_source = "method.request.header.Authorization"` and `default_action { allow {} }`.

## Validation Evidence

```bash
CLIENT=<client-id>; POOL=<pool-id>; API=<api_url>
# One-time: give the seeded user a permanent password
aws cognito-idp admin-set-user-password --user-pool-id "$POOL" \
  --username shopper@acme.example --password 'Passw0rd!23' --permanent

TOKEN=$(aws cognito-idp initiate-auth --client-id "$CLIENT" \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=shopper@acme.example,PASSWORD='Passw0rd!23' \
  --query 'AuthenticationResult.IdToken' --output text)

curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: $TOKEN" "$API/orders"   # 200
curl -s -o /dev/null -w '%{http_code}\n' "$API/orders"                              # 401
```

Backend Lambda now logs invocations for the authorized call.

## Common Mistakes

- **Fixing the authorizer but forgetting to redeploy the `prod` stage** → REST API changes don't take effect until deployed.
- **Using the Cognito access token when the authorizer expects the ID token** (or vice versa) — match your API's configuration.
- **Deleting the WAF entirely** to "make it work" — that removes protection. Flip the default action instead.
- **Setting default `Allow` but leaving the managed rule groups in `count` mode** — they then only observe, never block.

## Distinguish From Similar Failures

| Status | Body/context | Layer |
|--------|--------------|-------|
| `403` `{"message":"Forbidden"}` before any Lambda runs | WAF block or API resource policy (**fault 2**) |
| `401 Unauthorized` | Authorizer rejected: wrong identity source (**fault 1**), expired/wrong token, or wrong token *type* (ID vs access) |
| `403 Missing Authentication Token` | Not auth at all — wrong path/method on a REST API |
| Works in console test, fails for clients | Stage never redeployed after the fix |

## Key Takeaways / Exam Angle

- **Authorizer identity source must match the client's header, and REST API changes require a deployment.** Two classic exam gotchas in one.
- **`401` = authorizer, `403` = WAF/resource policy.** The status code routes your investigation.
- **WAF default action defines the security posture.** `Block` default = strict allow-list; `Allow` default + blocking rules = deny-list. Know which you intend.
