import os
import boto3

ddb = boto3.client("dynamodb")
TABLE = os.environ["TABLE_NAME"]


def handler(event, context):
    order_id = event["orderId"]
    ddb.put_item(TableName=TABLE, Item={"orderId": {"S": order_id}, "status": {"S": "SAVED"}})
    return {"orderId": order_id, "status": "SAVED"}
