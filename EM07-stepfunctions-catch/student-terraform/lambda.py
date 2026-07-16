def handler(event, context):
    # Simulates a flaky third-party payment gateway that is currently down.
    raise Exception("PaymentGatewayTimeout: processor unavailable")
