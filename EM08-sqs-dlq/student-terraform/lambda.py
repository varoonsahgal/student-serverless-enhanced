import json


def handler(event, context):
    for record in event["Records"]:
        data = json.loads(record["body"])  # non-JSON bodies raise here
        if data.get("poison"):
            raise ValueError("Cannot process poison order")
        print(f"processed order {data.get('orderId')}")
    return {"ok": True}
