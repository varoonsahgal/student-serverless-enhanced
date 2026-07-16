import json
import os
import boto3

sm = boto3.client("secretsmanager")
SECRET_ARN = os.environ["SECRET_ARN"]


def handler(event, context):
    resp = sm.get_secret_value(SecretId=SECRET_ARN)
    creds = json.loads(resp["SecretString"])
    # Pretend to connect using the retrieved credentials.
    return {"db": "connected", "user": creds["username"]}
