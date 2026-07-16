import json
import os
import boto3

sns = boto3.client("sns")
TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


def handler(event, context):
    # PostConfirmation event carries the confirmed user's attributes.
    email = event["request"]["userAttributes"]["email"]
    resp = sns.subscribe(
        TopicArn=TOPIC_ARN,
        Protocol="email",
        Endpoint=email,
        ReturnSubscriptionArn=True,
    )
    print(f"Subscribed {email}: {resp['SubscriptionArn']}")
    # PostConfirmation MUST return the original event.
    return event
