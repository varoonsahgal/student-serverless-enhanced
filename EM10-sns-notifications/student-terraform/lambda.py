import json
import os
import boto3

sns = boto3.client("sns")
TOPIC_ARN = os.environ["TOPIC_ARN"]


def handler(event, context):
    order = json.loads(event["body"]) if isinstance(event, dict) and "body" in event else event
    resp = sns.publish(
        TopicArn=TOPIC_ARN,
        Subject="Your Acme order",
        Message=json.dumps({"orderId": order.get("orderId", "o1"), "status": "CONFIRMED"}),
    )
    print(f"published messageId {resp['MessageId']}")
    return {"messageId": resp["MessageId"]}
