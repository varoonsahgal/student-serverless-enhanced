import json


def handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps({"orders": [{"id": "o-100", "status": "SHIPPED"}]}),
    }
