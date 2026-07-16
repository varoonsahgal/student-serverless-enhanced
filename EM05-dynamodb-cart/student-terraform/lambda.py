import json
import os
import boto3

ddb = boto3.resource("dynamodb")
TABLE = os.environ["TABLE_NAME"]

# BUG: the table's partition key is "userId". Using "user_id" here makes every
# read/write throw ValidationException. Solution sets KEY_ATTR = "userId".
KEY_ATTR = "user_id"


def _resp(status, body):
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def handler(event, context):
    method = event["requestContext"]["http"]["method"]
    qs = event.get("queryStringParameters") or {}
    user = qs.get("user", "anon")
    table = ddb.Table(TABLE)

    if method == "GET":
        resp = table.get_item(Key={KEY_ATTR: user})
        item = resp.get("Item", {"cart": []})
        return _resp(200, item)

    if method == "POST":
        body = json.loads(event.get("body") or "{}")
        product = body.get("item", "p1")
        table.update_item(
            Key={KEY_ATTR: user},
            UpdateExpression="SET cart = list_append(if_not_exists(cart, :empty), :p)",
            ExpressionAttributeValues={":p": [product], ":empty": []},
        )
        return _resp(200, {"message": "added", "user": user, "item": product})

    return _resp(405, {"message": "method not allowed"})
