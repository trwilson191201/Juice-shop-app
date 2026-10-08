# IaC Security Scan

The Terraform is scanned with **Checkov** against a full `terraform plan` (so every
resource inside the community VPC/EKS modules is evaluated, not just the module calls).

## How to reproduce

```bash
cd terraform
terraform plan -out=tfplan
terraform show -json tfplan > plan.json
checkov -f plan.json --compact --quiet   # reads .checkov.yaml for documented skips
```

## Result

| | Count |
|---|---|
| Passed | 123 |
| Failed | 0 |
| Fixed in code | 2 |
| Suppressed with justification | 9 (checks) |

Initial scan surfaced **12 failing checks**. They were triaged into three buckets.

## Fixed in code (real hardening)

| Check | Issue | Fix | Why it matters here |
|-------|-------|-----|---------------------|
| `CKV_AWS_37` | EKS control-plane logging not enabled for all types | `cluster_enabled_log_types = [api, audit, authenticator, controllerManager, scheduler]` | **Audit logs are the detection source** for the API-level attacks in the demo |
| `CKV_AWS_341` | Node IMDS hop limit > 1 | `http_tokens=required`, `http_put_response_hop_limit=1` on the node group | Blocks the classic **pod compromise → steal node IAM creds via IMDS/SSRF** path |

## False positives (plan-time or stale rule)

| Check | Why it's a false positive |
|-------|---------------------------|
| `CKV_AWS_339` "unsupported k8s version" | We run **1.36**, which is in AWS *standard support* — verified with `aws eks describe-cluster-versions`. Checkov's bundled version list simply lags the API. |
| `CKV2_AWS_19` EIP unattached | The EIP attaches to the NAT gateway **on apply**; it only looks orphaned in a plan. |
| `CKV2_AWS_5` SG unattached | Cluster/node security groups bind to ENIs **on apply**; plan-time artifact. |

## Accepted lab tradeoffs (would revisit in prod)

| Check | Decision |
|-------|----------|
| `CKV_AWS_38` / `CKV_AWS_39` public API endpoint | Needed to `kubectl` from the demo laptop. Mitigated by locking the endpoint to `admin_cidr` (your IP) rather than `0.0.0.0/0`. |
| `CKV_AWS_382` node egress `0.0.0.0/0` | EKS module default; nodes must pull images and reach the API. Pod egress is constrained by the hardened default-deny `NetworkPolicy`. |
| `CKV_AWS_158` / `CKV_AWS_338` log KMS + 1-yr retention | No value for an ephemeral lab destroyed after the demo. |
| `CKV2_AWS_11` VPC flow logs | Strong prod control; listed in the secure-architecture recommendations. Skipped here to avoid cost. |

Suppressions live in [`terraform/.checkov.yaml`](../terraform/.checkov.yaml), each with an
inline justification — responsible suppression, not a blanket mute.

## Talk track

"I scan my IaC the same way I'd scan the app. Twelve findings — I fixed the two that
materially reduce blast radius and happen to map to this demo (audit logging for
detection, IMDSv2 to stop credential theft from a compromised pod), confirmed three
were scanner false-positives, and consciously accepted the rest as lab tradeoffs I've
documented. In a prod pipeline this scan is a CI gate."
