# EM01 — Checkout 404: API Gateway Routing Blackout — Solution Handout

> Instructor answer key. Reveals the full diagnosis and fix.

## Original Symptoms

- `GET /products` and `GET /cart` → **HTTP 500** (`Internal Server Error`).
- `POST /place-order` → **HTTP 404** (`Not Found`).
- Browser preflight `OPTIONS` fails with a CORS error.

## Root Causes (three planted faults)

| # | Fault | Where | Effect |
|---|-------|-------|--------|
| 1 | Integration `payload_format_version = "1.0"` | HTTP API integration | Lambda receives a **1.0** event but reads **2.0** fields (`requestContext.http.method`, `rawPath`) → `KeyError` → 500 |
| 2 | No route for `POST /place-order` | HTTP API routes | API Gateway has nothing to match → **404** before Lambda is ever called |
| 3 | No `cors_configuration` on the API | HTTP API | Preflight `OPTIONS` is not auto-answered → browser CORS failure |

### Why it happened

The storefront Lambda was written for the modern **2.0** payload format. Someone set the integration to **1.0** (the older format, closer to REST API events). Under 1.0 there is no `event["requestContext"]["http"]` block, so `event["requestContext"]["http"]["method"]` raises `KeyError`, which API Gateway surfaces as a generic `500`. Separately, the `/place-order` route was never added, and CORS was never configured.

## Exact Fix

### Option A — AWS Console

1. **Fix the payload format (fault 1):**
   - API Gateway → your HTTP API → **Develop → Integrations**.
   - Select the Lambda integration → **Edit**.
   - Change **Payload format version** from `1.0` to **`2.0`** → **Save**.
2. **Add the missing route (fault 2):**
   - **Develop → Routes → Create**.
   - Method **POST**, path **`/place-order`** → **Create**.
   - Select the new route → **Attach integration** → choose the existing storefront Lambda integration.
3. **Configure CORS (fault 3):**
   - **Develop → CORS → Configure**.
   - `Access-Control-Allow-Origin`: `*` (or `https://acme.example`).
   - `Access-Control-Allow-Methods`: `GET, POST, OPTIONS`.
   - `Access-Control-Allow-Headers`: `content-type, authorization`.
   - **Save.**
4. HTTP APIs with a `$default` stage set to **auto-deploy** publish changes immediately — no manual deploy needed. (If you use a named stage without auto-deploy, deploy it.)

### Option B — AWS CLI

```bash
API_ID=<your http api id>          # aws apigatewayv2 get-apis
INTEG_ID=<integration id>          # aws apigatewayv2 get-integrations --api-id $API_ID
LAMBDA_ARN=<storefront lambda arn>

# Fault 1: payload format 1.0 -> 2.0
aws apigatewayv2 update-integration \
  --api-id "$API_ID" --integration-id "$INTEG_ID" \
  --payload-format-version 2.0

# Fault 2: add POST /place-order
aws apigatewayv2 create-route \
  --api-id "$API_ID" \
  --route-key 'POST /place-order' \
  --target "integrations/$INTEG_ID"

# Fault 3: add CORS
aws apigatewayv2 update-api \
  --api-id "$API_ID" \
  --cors-configuration 'AllowOrigins=*,AllowMethods=GET,POST,OPTIONS,AllowHeaders=content-type,authorization'
```

> The **permanent** fix (what the solution Terraform does) is to set `payload_format_version = "2.0"`, add the `POST /place-order` route + integration, and add a `cors_configuration` block. Console/CLI edits are lost on the next `terraform apply`.

## Validation Evidence

```bash
API=<api_endpoint>

curl -s "$API/products" ; echo
# {"products":[{"id":"p1","name":"Acme Widget","price":19.99}, ...]}   HTTP 200

curl -s -o /dev/null -w '%{http_code}\n' -X POST "$API/place-order" -d '{"items":["p1"]}'
# 200

curl -s -i -X OPTIONS "$API/products" \
  -H 'Origin: https://acme.example' \
  -H 'Access-Control-Request-Method: GET' | grep -i access-control-allow-origin
# access-control-allow-origin: *
```

CloudWatch: after the fix, the storefront Lambda log shows successful invocations with **no `KeyError` traceback**.

## Common Mistakes

- **Fixing only the Lambda code** to read 1.0 fields. That works, but the storefront app and other integrations expect 2.0 — align on 2.0.
- **Adding the route but forgetting to attach the integration** → route exists but returns `500`/`Internal configuration error`.
- **Returning CORS headers only from the Lambda.** That does not answer the preflight `OPTIONS`; the API needs a CORS config.
- **Editing a named stage without auto-deploy** and forgetting to deploy → your change never goes live.

## Distinguish From Similar Failures

| Symptom | This lab? | Actually is |
|---------|-----------|-------------|
| `500` on every route at once | ✅ | Payload-format mismatch (one shared contract broken) |
| `502 Bad Gateway` | ❌ | Lambda returned a malformed proxy response (missing `statusCode`/`body`) |
| `404` on one route only | ✅ | That route was never created |
| `403 Missing Authentication Token` | ❌ | Wrong URL path/stage — the request never matched the API |
| CORS error only in browser, `curl` fine | ✅ | No API-level CORS config (preflight unanswered) |

## Key Takeaways / Exam Angle

- **500 vs 404 tells you the layer.** 500 = your integration/Lambda; 404 = no matching route. Read the status code first.
- **Payload format version is a top-3 API Gateway HTTP-API exam trap.** Know that 2.0 puts method/path under `requestContext.http` / `rawPath`.
- **CORS is an API-level concern** for HTTP APIs — configure it on the API, and remember preflight `OPTIONS`.
- **`$default` stage + auto-deploy** means no manual deploy step; named stages may need one.
