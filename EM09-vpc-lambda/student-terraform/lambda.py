import os
import boto3
from botocore.config import Config

# Short timeouts so a missing route fails fast (instead of the full Lambda timeout).
cfg = Config(connect_timeout=3, read_timeout=3, retries={"max_attempts": 1})
ddb = boto3.client("dynamodb", config=cfg)
TABLE = os.environ["TABLE_NAME"]


def handler(event, context):
    ddb.put_item(TableName=TABLE, Item={"pk": {"S": "healthcheck"}, "ts": {"S": "now"}})
    resp = ddb.get_item(TableName=TABLE, Key={"pk": {"S": "healthcheck"}})
    return {"ok": True, "item": resp.get("Item")}
