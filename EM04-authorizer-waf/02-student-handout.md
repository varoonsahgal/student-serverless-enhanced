# EM04 — The Locked Front Door: Cognito Authorizer + WAF — Student Handout

> **Region:** All lab resources are deployed in **US West (Oregon) — `us-west-2`**. Before running any AWS CLI command or opening the console, confirm your region is `us-west-2`. If you are in the wrong region, your resources will not exist and every command will fail.


## Lab Goals

- Configure an Amazon API Gateway **REST API** Cognito **authorizer** correctly.
- Understand how the authorizer's **identity source** must match the header clients send.
- Understand how an **AWS WAF** web ACL's **default action** gates every request.

## Scenario

**Acme Retail** protects its order API two ways: only signed-in customers (Cognito) may call it, and AWS WAF filters hostile traffic. After the lead engineer left, **every** request fails — even a perfectly valid, logged-in customer with a fresh token gets rejected. The security layer has become a brick wall.

**Microcredential mapping:** this lab mirrors **Challenge 3** of the assessment (create a Cognito authorizer with token source `Authorization`, attach AWS WAF managed rule groups, and keep legitimate traffic flowing).

## Architecture

```
Client (Cognito ID token in "Authorization" header)
      │
      ▼
   AWS WAF web ACL  ──(default action?)──▶  API Gateway REST API (prod)
                                              │  Cognito authorizer (identity source?)
                                              ▼
                                           GET /orders ─▶ Lambda
```

## Starting Symptom

1. A valid Cognito **ID token** in the `Authorization` header still returns **`401 Unauthorized`**.
2. Even calls that *should* pass return **`403 Forbidden`** with a WAF-style body (`{"message":"Forbidden"}`) before reaching the API.
3. The backend Lambda shows **no invocations** — nothing gets through.

## Time Limit

**40 minutes.**

## Guided Investigation Hints

1. A Cognito authorizer only reads the token from the header named in its **Identity source** (e.g. `method.request.header.Authorization`). If that setting names a different header than the client uses, every request is `401`.
2. `401` = authorizer rejected. `403` from WAF = the web ACL blocked it. You may be hitting **both** gates — fix them independently.
3. A WAF web ACL has a **default action**: `Allow` or `Block`. If the default is **Block** and no rule explicitly allows the request, everything is blocked.
4. Get a real token to test with:
   ```bash
   aws cognito-idp initiate-auth --client-id <client> \
     --auth-flow USER_PASSWORD_AUTH \
     --auth-parameters USERNAME=<user>,PASSWORD=<pw>
   # use the IdToken from the response
   curl -i -H "Authorization: <IdToken>" <api_url>/orders
   ```

## Debugging Playbook (How a Pro Thinks)

Security layers evaluate **in order**, so debug them in order — outermost first:

```
request ─▶ WAF (403 if blocked) ─▶ API Gateway auth (401 if rejected) ─▶ Lambda
```

If everything returns `403`, you can't even *see* whether the authorizer works — fix the WAF gate first, then re-test to expose the next layer. This "peel the onion" order matters in every layered system.

Two mental models to keep:
- A WAF **default action** is your security *posture*: `Block` default = allow-list (only rule-matched traffic passes); `Allow` default = deny-list (rules remove bad traffic). Managed reputation rules assume a deny-list posture.
- An authorizer's **identity source** is a pointer, not a suggestion: it reads *exactly* the header named there. `Auth` ≠ `Authorization`, and no fallback exists.

And burn this in: **REST API changes do nothing until you deploy the stage.** "I fixed it but nothing changed" = undeployed change, more often than not.

## Things to Check

- **API Gateway → your REST API → Authorizers:** what is the **Identity source**?
- **API Gateway → Resources → GET /orders → Method Request:** is the Cognito authorizer attached?
- **WAF & Shield → Web ACLs → your ACL:** what is the **Default web ACL action**?
- **CloudWatch:** does the backend Lambda log anything at all?

## Validation Criteria

You are done when:

1. A request **with** a valid Cognito ID token in `Authorization` → **`200`** and the Lambda logs an invocation.
2. A request **without** a token → **`401`** (auth still enforced).
3. The WAF web ACL still evaluates requests (managed rule groups attached), but legitimate traffic is **allowed**.

## Key Takeaways

- **The authorizer's identity source must exactly match the header the client sends.** Mismatch = `401` for everyone.
- **`401` vs `403` tells you which gate failed:** `401` = authorizer; `403` = WAF (or resource policy).
- **A WAF default action of `Block` denies everything not explicitly allowed.** For an allow-listing posture you usually want default `Allow` + rules that block bad traffic.

## Reflection Questions

1. Why might a security team accidentally set a WAF default action to `Block` and lock out all users?
2. How would you tell an authorizer failure from a WAF block using only the HTTP status code and response body?
3. What's the difference between using the Cognito **ID token** vs **access token** at an authorizer?
