# EM05 — The Vanishing Cart — Solution Handout

> Instructor answer key.

## Original Symptom

`POST`/`GET /cart` return `500`; the log shows a DynamoDB `ValidationException` about the key.

## Root Cause

The cart table's partition key is **`userId`**, but the Lambda passes its key as **`user_id`** (`Key={"user_id": user}`). DynamoDB rejects every read and write with:

```
ValidationException: The provided key element does not match the schema
```

Because writes never succeed, nothing persists — hence the "vanishing cart."

## Exact Fix

The permanent fix is in the Lambda code: use the attribute name that matches the table's key schema. The **solution Terraform** ships a `lambda.py` whose `KEY_ATTR = "userId"`.

### Fix via code (recommended)

Change the key attribute constant in the function from `user_id` to `userId`:

```python
KEY_ATTR = "userId"   # was "user_id"
```

Redeploy the function. Via CLI, after editing and re-zipping:

```bash
zip -j fn.zip lambda.py
aws lambda update-function-code \
  --function-name <cart-fn> \
  --zip-file fileb://fn.zip
```

(Or re-run the solution Terraform, which packages the corrected code.)

### Why not change the table?

You *could* recreate the table with hash key `user_id` to match the code, but changing a DynamoDB partition key requires **deleting and recreating** the table (losing data). Aligning the code is faster and non-destructive — prefer it.

## Validation Evidence

```bash
API=<api_endpoint>
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$API/cart?user=alice" -d '{"item":"p1"}'   # 200
curl -s -X POST "$API/cart?user=alice" -d '{"item":"p2"}' >/dev/null
curl -s "$API/cart?user=alice" ; echo
# {"userId":"alice","cart":["p1","p2"]}

curl -s "$API/cart?user=bob" ; echo
# {"cart":[]}    (separate user, separate cart)
```

DynamoDB **Explore items** now shows an item with partition key `alice` and a `cart` list.

## Common Mistakes

- **Recreating the table with `user_id`** to match the buggy code — works, but destroys data and is the wrong instinct. Fix the code.
- **Fixing only `get_item` and not `update_item`** (or vice versa) — both must use `userId`.
- **Assuming an empty cart on GET means "not persisted"** when the real error is on the `500` write. Read the write path's log first.

## Distinguish From Similar Failures

| Exception | Diagnosis |
|-----------|-----------|
| `ValidationException` (key element does not match schema) | Key **name** mismatch (**this lab**) |
| `ResourceNotFoundException` | Wrong **table name** or region (check `TABLE_NAME` env var) |
| `AccessDeniedException` | IAM — role can't `GetItem`/`UpdateItem` on this table |
| No error, but data "vanishes" | Writing to a *different* (existing) table, or key value differs between write and read |

## Key Takeaways / Exam Angle

- **`ValidationException: provided key element does not match the schema` = key-name mismatch.** Top DynamoDB exam signal.
- **Prefer code changes over table re-creation** when the two disagree; changing a key schema is destructive.
- **Consistent per-user keys give you per-user isolation for free** — a core DynamoDB modeling idea.
