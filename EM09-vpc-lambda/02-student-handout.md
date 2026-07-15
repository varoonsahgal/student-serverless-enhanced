# EM09 — Lambda in the Network Cage: VPC Connectivity — Student Handout

> **Region:** All lab resources are deployed in **US West (Oregon) — `us-west-2`**. Before running any AWS CLI command or opening the console, confirm your region is `us-west-2`. If you are in the wrong region, your resources will not exist and every command will fail.


## Lab Goals

- Understand what changes when a Lambda runs **inside a VPC**.
- Diagnose a **timeout** to an AWS service caused by missing network routing.
- Restore connectivity with a **VPC endpoint** (no NAT).

## Scenario

For a new security requirement, **Acme Retail** moved a data-access Lambda into a private VPC subnet. Immediately, the function started **timing out** on every DynamoDB call. The security intent was right — but the network path to DynamoDB was never provided, so the function is now sealed in a cage with no way out.

**Microcredential mapping:** this lab mirrors **Challenge 6** of the assessment (run Lambdas inside VPC private subnets with the right routing so they can still reach AWS services).

## Architecture

```
invoke ─▶ Lambda (in VPC private subnet, security group attached)
                 │  DynamoDB API call
                 ▼
           ??? no route to DynamoDB ???  ──▶  DynamoDB   (never reached)
```

## Starting Symptom

1. `aws lambda invoke` → the function **errors after a few seconds** with a connection/endpoint timeout to DynamoDB.
2. The CloudWatch log shows a `Connect timeout` / `EndpointConnectionError` reaching `dynamodb.<region>.amazonaws.com`.
3. The same code worked before the function was placed in the VPC.

## Time Limit

**35 minutes.**

## Guided Investigation Hints

1. A Lambda in a **private** subnet has **no public internet path** and no automatic route to AWS service public endpoints unless you provide one (NAT Gateway, or — for supported services — a **VPC endpoint**).
2. DynamoDB (and S3) support **Gateway VPC endpoints**, which are **free** and add a route in the subnet's **route table** so traffic reaches the service privately. This is the preferred fix (no NAT cost).
3. Check the subnet's **route table**: is there any route to DynamoDB (a prefix-list route via a gateway endpoint)?
4. Confirm the **security group** allows outbound (egress) — but note that egress being open still isn't enough without a route.

## Debugging Playbook (How a Pro Thinks)

**Speed of failure is a diagnostic.** IAM denials come back in milliseconds; network problems *hang, then time out*. A Lambda that stalls for seconds before erroring is almost never a permissions problem — stop reading IAM policies and start tracing the network path:

1. **Route table** of the Lambda's subnet: is there any route to the target service (gateway endpoint prefix list, NAT, IGW)?
2. **VPC endpoint**: does one exist, and is it associated with *this* subnet's route table?
3. **Security group egress**: open? (Necessary, but egress without a route is a car with no road.)
4. **NACLs**: rarely the culprit, check last.

Cost-aware fix selection: DynamoDB and S3 support **Gateway endpoints — free, route-table based**. A NAT Gateway also "works" but costs ~$32/month + data forever. Choosing the free endpoint over reflexively adding NAT is exactly the judgment this lab (and the exam) tests.

## Things to Check

- **Lambda → Configuration → VPC:** which subnets and security group?
- **VPC → Route tables →** the subnet's route table: any DynamoDB/S3 gateway-endpoint route?
- **VPC → Endpoints:** does a **Gateway** endpoint for `dynamodb` exist and is it associated with the route table?
- **CloudWatch Logs:** the exact timeout/endpoint error.

## Validation Criteria

You are done when:

1. `aws lambda invoke` returns **`{"ok": true, ...}`** (the DynamoDB read/write succeeds).
2. No timeout/`EndpointConnectionError` in the logs.
3. You used a **Gateway VPC endpoint** (no NAT Gateway) so there is no per-hour egress cost.

## Key Takeaways

- **A VPC Lambda loses its default path to AWS service endpoints.** You must add NAT or a VPC endpoint.
- **DynamoDB and S3 use free Gateway endpoints** that add a route-table entry — prefer them over NAT for those services.
- **Open egress on the security group is necessary but not sufficient** — without a *route*, packets have nowhere to go.

## Reflection Questions

1. Why is a Gateway endpoint for DynamoDB usually better than a NAT Gateway here?
2. What's the difference between a **Gateway** endpoint and an **Interface** endpoint, and which services use which?
3. How would you reach a service that only supports Interface endpoints (e.g., Secrets Manager) from a private subnet?
