import json
import os
import boto3

sfn = boto3.client("stepfunctions")
SM_ARN = os.environ["STATE_MACHINE_ARN"]


def handler(event, context):
    body = json.loads(event.get("body") or "{}")
    resp = sfn.start_execution(
        stateMachineArn=SM_ARN,
        input=json.dumps({"order": body}),
    )
    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps({"executionArn": resp["executionArn"], "status": "STARTED"}),
    }
