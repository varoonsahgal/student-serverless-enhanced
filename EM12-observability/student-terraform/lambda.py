def handler(event, context):
    print("order-intake: starting")
    # BUG: invoked with {"orderId": "..."}, but this reads event["order"]["id"].
    order_id = event["order"]["id"]
    return {"orderId": order_id, "status": "OK"}
