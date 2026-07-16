import json
import os
import boto3

ddb = boto3.client("dynamodb")
sfn = boto3.client("stepfunctions")
TABLE = os.environ["TABLE_NAME"]
SM = os.environ["STATE_MACHINE_ARN"]


def handler(event, context):
    method = event["requestContext"]["http"]["method"]  # requires payload format 2.0
    body = json.loads(event.get("body") or "{}")
    order_id = body.get("orderId", "o-" + context.aws_request_id[:8])
    ddb.put_item(TableName=TABLE, Item={"orderId": {"S": order_id}, "status": {"S": "NEW"}})
    resp = sfn.start_execution(stateMachineArn=SM, input=json.dumps({"orderId": order_id}))
    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps({"orderId": order_id, "execution": resp["executionArn"]}),
    }
