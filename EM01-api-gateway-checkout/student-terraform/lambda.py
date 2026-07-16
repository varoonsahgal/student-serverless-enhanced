import json

PRODUCTS = [
    {"id": "p1", "name": "Acme Widget", "price": 19.99},
    {"id": "p2", "name": "Acme Gadget", "price": 34.50},
    {"id": "p3", "name": "Acme Gizmo", "price": 8.25},
]


def _resp(status, body):
    return {
        "statusCode": status,
        "headers": {
            "content-type": "application/json",
            "access-control-allow-origin": "*",
        },
        "body": json.dumps(body),
    }


def handler(event, context):
    # This handler expects payload format version 2.0.
    method = event["requestContext"]["http"]["method"]
    path = event["rawPath"]

    if path == "/products" and method == "GET":
        return _resp(200, {"products": PRODUCTS})
    if path == "/cart" and method == "GET":
        return _resp(200, {"cart": [], "message": "empty cart"})
    if path == "/cart" and method == "POST":
        return _resp(200, {"cart": ["p1"], "message": "item added"})
    if path == "/place-order" and method == "POST":
        return _resp(200, {"orderId": "ord-123", "status": "CONFIRMED"})

    return _resp(404, {"message": "route not handled by function"})
