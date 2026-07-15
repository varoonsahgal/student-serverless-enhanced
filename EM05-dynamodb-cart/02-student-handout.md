# EM05 — The Vanishing Cart: DynamoDB Persistence — Student Handout

> **Region:** All lab resources are deployed in **US West (Oregon) — `us-west-2`**. Before running any AWS CLI command or opening the console, confirm your region is `us-west-2`. If you are in the wrong region, your resources will not exist and every command will fail.


## Lab Goals

- Understand how a DynamoDB **key schema** must match the keys your code uses.
- Read and interpret a `ValidationException` from DynamoDB.
- Prove persistence across separate requests.

## Scenario

**Acme Retail** shoppers keep losing their carts. Add three items, refresh, and the cart is empty again. Worse, adding an item throws a server error. With the sale minutes away, customers can't hold anything in their basket.

**Microcredential mapping:** this lab mirrors **Challenge 4** of the assessment (restore shopping-cart persistence: consistent user key, correct DynamoDB table/key schema, clean CloudWatch logs).

## Architecture

```
curl POST /cart?user=alice  {"item":"p1"}
curl GET  /cart?user=alice
        │
        ▼
   HTTP API ─▶ Lambda (cart) ──▶ DynamoDB table  (hash key: userId)
```

## Starting Symptom

1. `POST /cart?user=alice` → **HTTP 500**.
2. `GET /cart?user=alice` → **HTTP 500** (or an empty cart that never fills).
3. The cart Lambda's CloudWatch log shows a **`ValidationException`** mentioning the key.

## Time Limit

**30 minutes.**

## Guided Investigation Hints

1. A DynamoDB `ValidationException: The provided key element does not match the schema` means the **attribute name** in your `Key={...}` does not match the table's **partition key name**.
2. Compare two things: the table's partition key name (DynamoDB console → your table → **Indexes/Overview**) and the attribute name the Lambda passes in `get_item`/`update_item`.
3. This is a **code vs. schema** mismatch. Either the code or the table is "right" — decide which to align. (Changing a table's key requires recreating it; changing the code is cheaper.)
4. Test persistence directly:
   ```bash
   curl -s -X POST "$API/cart?user=alice" -d '{"item":"p1"}'
   curl -s "$API/cart?user=alice"
   ```

## Debugging Playbook (How a Pro Thinks)

DynamoDB exceptions are self-sorting — the exception name routes your investigation:

| Exception | Meaning | Look at |
|-----------|---------|---------|
| `ValidationException` (key element) | Request shape ≠ table schema | Key names in code vs table's partition key |
| `ResourceNotFoundException` | Wrong table name / region | `TABLE_NAME` env var, region config |
| `AccessDeniedException` | IAM | Role policy actions + resource ARN |
| `ConditionalCheckFailedException` | Your own condition expression | Business logic, idempotency guards |

Here the schema and the code disagree about one attribute name. When code and schema disagree, ask: **which is cheaper to change?** Changing a DynamoDB partition key means delete-and-recreate the table (destructive); changing one constant in code is a redeploy. In incident mode, always take the reversible, non-destructive path first.

## Things to Check

- **DynamoDB → your table → Overview:** what is the **Partition key** name?
- **Lambda → cart function → Code / Environment:** what attribute name does it use for the key?
- **CloudWatch Logs:** the exact `ValidationException` text.
- **DynamoDB → Explore items:** are any items being written at all?

## Validation Criteria

You are done when:

1. `POST /cart?user=alice {"item":"p1"}` → **200**.
2. A second `POST` adds another item; `GET /cart?user=alice` → **200** returning **both** items.
3. `GET /cart?user=bob` returns a **separate** cart (data isolated per user).

## Key Takeaways

- **DynamoDB `Key` attribute names must match the table's key schema exactly.** A typo = `ValidationException`, not silent behavior.
- **`ValidationException` on the key is a schema-vs-code mismatch** — read the message; it names the offending key.
- **Persistence needs a stable, consistent key per user.** Same user → same partition key → same item.

## Reflection Questions

1. Why is it usually cheaper to fix the code than to change a table's key schema?
2. How would you store multiple carts per user (e.g., saved-for-later) without changing the partition key?
3. What would happen if two users shared the same partition-key value?
