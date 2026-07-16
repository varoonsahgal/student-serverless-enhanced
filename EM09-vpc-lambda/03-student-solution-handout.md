# EM09 — Lambda in the Network Cage — Solution Handout

> Instructor answer key.

## Original Symptom

A VPC-attached Lambda times out on every DynamoDB call with `EndpointConnectionError` / connect timeout.

## Root Cause

The Lambda runs in a **private subnet** whose route table has **only the local route** — there is **no path to DynamoDB** (no NAT Gateway and no Gateway VPC endpoint). The security group allows egress, but with no route the DynamoDB API request never leaves the subnet and times out.

## Exact Fix

Create a **Gateway VPC endpoint for DynamoDB** and associate it with the subnet's route table. Gateway endpoints are free and require no NAT.

### Console

1. VPC → **Endpoints → Create endpoint**.
2. Service category **AWS services** → search `dynamodb` → select `com.amazonaws.<region>.dynamodb` (type **Gateway**).
3. Choose the lab **VPC**.
4. Under **Route tables**, select the private subnet's route table.
5. **Create endpoint.**

### CLI

```bash
VPC_ID=<vpc id>
RT_ID=<route table id>
REGION=<region>

aws ec2 create-vpc-endpoint \
  --vpc-id "$VPC_ID" \
  --vpc-endpoint-type Gateway \
  --service-name "com.amazonaws.$REGION.dynamodb" \
  --route-table-ids "$RT_ID"
```

> Permanent fix (solution Terraform): an `aws_vpc_endpoint` of type `Gateway` for `com.amazonaws.<region>.dynamodb`, associated with the private route table.

## Validation Evidence

```bash
FN=<function name>
aws lambda invoke --function-name "$FN" /tmp/out.json >/dev/null && cat /tmp/out.json
# {"ok": true, "item": {"pk": {"S": "healthcheck"}, ...}}
```

Logs no longer show any `EndpointConnectionError`; the put/get complete in milliseconds.

## Common Mistakes

- **Adding a NAT Gateway** — it works but costs ~$32/mo + data; unnecessary for DynamoDB/S3. Use the free Gateway endpoint.
- **Creating the endpoint but not associating the route table** — the route must be added to the subnet's route table.
- **Opening the security group more** — egress was never the blocker; routing was.
- **Using an Interface endpoint for DynamoDB** — DynamoDB uses a **Gateway** endpoint; Interface endpoints are for services like Secrets Manager/KMS.

## Distinguish From Similar Failures

| Symptom | Diagnosis |
|---------|-----------|
| Slow hang → connect timeout | No network route: missing endpoint/NAT (**this lab**) |
| Instant `AccessDeniedException` | IAM — permissions, not networking |
| DNS resolution failure (`could not resolve endpoint`) | Interface-endpoint scenario with private DNS off, or VPC DNS disabled |
| Timeout only under load | ENI/IP exhaustion in the subnet, not a missing route |
| Worked before VPC attachment, broke after | The defining fingerprint of a VPC networking gap |

## Key Takeaways / Exam Angle

- **VPC-attached Lambdas need an explicit path** (NAT or VPC endpoint) to reach AWS service endpoints.
- **Gateway endpoints (DynamoDB, S3) are free and route-table based**; Interface endpoints (most other services) are ENI/DNS based and cost per hour.
- **Timeout to a service endpoint from a private subnet = missing route**, not an IAM or code problem.
