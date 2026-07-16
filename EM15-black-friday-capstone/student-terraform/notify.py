import json
import os
import boto3

sns = boto3.client("sns")
TOPIC = os.environ["TOPIC_ARN"]


def handler(event, context):
    order_id = event.get("orderId", "?")
    r = sns.publish(TopicArn=TOPIC, Message=json.dumps({"orderId": order_id, "status": "CONFIRMED"}))
    print(f"published {r['MessageId']}")
    return {"messageId": r["MessageId"]}
