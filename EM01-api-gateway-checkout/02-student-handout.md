# EM01 — Checkout 404: API Gateway Routing Blackout — Student Handout

> **Region:** All lab resources are deployed in **US West (Oregon) — `us-west-2`**. Before running any AWS CLI command or opening the console, confirm your region is `us-west-2`. If you are in the wrong region, your resources will not exist and every command will fail.


## Lab Goals

- Diagnose why an Amazon API Gateway **HTTP API** returns `500` and `404` for a Lambda-backed storefront.
- Understand the difference between **payload format version 1.0 and 2.0** and how it changes the event your Lambda receives.
- Confirm that a route exists, is integrated, and that **CORS** is configured for browsers.

## Scenario

You are the on-call engineer at **Acme Retail**. The lead engineer quit two hours before a flash sale. The storefront's API — the single door between the web app and every Lambda — is misbehaving. The web team is screaming: "Products won't load, and checkout throws a 404!"

## Architecture

```
Browser / curl
      │  HTTPS
      ▼
┌──────────────────────────────┐
│  API Gateway (HTTP API)      │
│   GET  /products ───────┐    │
│   GET  /cart ───────────┼──▶ │  Lambda (storefront)
│   POST /cart ───────────┘    │   routes on rawPath + method
│   POST /place-order  ??? │    │
└──────────────────────────────┘
```

## Starting Symptoms

Using the `api_endpoint` value your instructor gives you (from `terraform output`):

1. `GET {api_endpoint}/products` → **HTTP 500** `{"message":"Internal Server Error"}`.
2. `GET {api_endpoint}/cart` → **HTTP 500**.
3. `POST {api_endpoint}/place-order` → **HTTP 404** `{"message":"Not Found"}`.
4. The web app console shows **CORS errors** ("No 'Access-Control-Allow-Origin' header") when it tries a preflight `OPTIONS` call.

## Time Limit

**35 minutes.**

## Guided Investigation Hints

1. A `500` from a proxy integration usually means **the Lambda raised an exception**. Open the storefront Lambda's CloudWatch Logs and read the traceback — what key is it trying to read from the event?
2. HTTP APIs support two **payload format versions**. In **2.0**, the method lives at `event["requestContext"]["http"]["method"]` and the path at `event["rawPath"]`. In **1.0**, those fields don't exist (it uses `httpMethod`/`path`). If the Lambda expects one format but the integration sends the other, you get a `KeyError`.
3. A `404` from API Gateway (not from Lambda) means **there is no route** matching that method + path. List the API's routes and compare them to what the app calls.
4. Browser calls do a preflight `OPTIONS`. HTTP APIs only answer preflight automatically if the API has a **CORS configuration**. Check whether one exists.

## Debugging Playbook (How a Pro Thinks)

Triage an API failure **by layer, using the status code as a router**:

| Signal | Layer | First move |
|--------|-------|-----------|
| `404 Not Found` (API Gateway body) | Routing | List routes; compare method + path exactly |
| `500 Internal Server Error` | Your Lambda threw | Read the CloudWatch traceback — never guess |
| `403 Missing Authentication Token` | Wrong URL/path shape | Check the full invoke URL you're hitting |
| Browser-only failure, `curl` works | CORS / preflight | Test `OPTIONS` with `Origin` + `Access-Control-Request-Method` headers |

Mental model: the **payload format version is a contract between the door (API Gateway) and the room (Lambda)**. Version 1.0 and 2.0 lay out the event differently (`httpMethod`/`path` vs `requestContext.http.method`/`rawPath`). If the two sides disagree, the handler dies on its very first line — which is why *every* route 500s at once. One global symptom across all routes usually means one shared misconfiguration, not many bugs.

## Things to Check

- **CloudWatch → Log groups →** the storefront Lambda log group: read the exception.
- **API Gateway → your HTTP API → Integrations:** what *payload format version* is set?
- **API Gateway → your HTTP API → Routes:** is `POST /place-order` listed?
- **API Gateway → your HTTP API → CORS:** is anything configured?

## Validation Criteria

You are done when:

1. `GET {api_endpoint}/products` → **200** with a JSON product list.
2. `GET {api_endpoint}/cart` → **200**.
3. `POST {api_endpoint}/place-order` → **200** with an order confirmation JSON.
4. `curl -i -X OPTIONS {api_endpoint}/products -H 'Origin: https://acme.example' -H 'Access-Control-Request-Method: GET'` returns **204** with an `access-control-allow-origin` header.

## Key Takeaways

- **A proxy-integration `500` is almost always your Lambda throwing** — read the log traceback before touching the API.
- **Payload format version changes the event shape.** 2.0 ≠ 1.0. Match your handler to the version, or you get `KeyError` on every request.
- **API Gateway returns `404` for unmatched routes; Lambda returns `500` for code errors.** The status code tells you *which side* to look at.
- **Browsers need CORS on the API**, not just an `Access-Control-Allow-Origin` header from your Lambda. Preflight `OPTIONS` must be answered.

## Reflection Questions

1. How could you tell, from the status code alone, that `/place-order` was a routing problem and `/products` was a code problem?
2. If you fixed the Lambda but left the payload version at 1.0, what would you change in the handler instead?
3. Why is answering preflight `OPTIONS` at the API layer safer than doing it in every Lambda?
