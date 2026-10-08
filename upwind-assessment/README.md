# Upwind SA Assessment — Kubernetes Security Lab

A reproducible, Terraform-provisioned **EKS** lab running **OWASP Juice Shop**, used to
demonstrate three OWASP Top 10 vulnerabilities, their mitigations, and an incident-
response walkthrough.

```
upwind-assessment/
├── README.md               ← you are here (deploy + teardown)
├── terraform/              ← EKS cluster, VPC, node group (IaC)
├── k8s/                    ← Juice Shop (vulnerable baseline)
│   └── hardened/           ← hardened overlay + NetworkPolicy (mitigations)
└── docs/
    ├── architecture.md     ← topology diagram + design tradeoffs
    ├── runbook.md          ← live exploit + mitigation steps
    ├── incident-response.md← extra-credit IR walkthrough
    └── slides-outline.md   ← 30–45 min presentation structure
```

## Prerequisites
- AWS account + credentials configured (`aws sts get-caller-identity` works)
- `terraform` >= 1.6, `kubectl`, `aws` CLI v2, and `jq`
- A region with EKS available (default `us-east-1`)

> **Cost:** EKS control plane (~$0.10/hr) + 2× t3.medium + 1 NAT gateway + 1 ELB.
> Ballpark **$5–10/day**. Run `terraform destroy` when you're not actively using it.

## 1. Provision the cluster

```bash
cd terraform
terraform init

# Restrict the API endpoint to your IP (recommended):
export TF_VAR_admin_cidr="$(curl -s https://checkip.amazonaws.com)/32"

terraform apply      # ~15 min
```

## 2. Point kubectl at it

```bash
# terraform prints this exact command as the 'configure_kubectl' output
aws eks update-kubeconfig --region us-east-1 --name upwind-lab
kubectl get nodes
```

## 3. Deploy Juice Shop (vulnerable baseline)

```bash
cd ..
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/juice-shop.yaml
kubectl -n juice-shop rollout status deploy/juice-shop

# Grab the public URL (ELB takes 2–3 min to come up)
export JUICE=http://$(kubectl -n juice-shop get svc juice-shop \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "$JUICE"
```

Open `$JUICE` in a browser — you should see Juice Shop.

## 4. Run the demo

Follow **[docs/runbook.md](docs/runbook.md)** for the three exploits, then apply the
hardened overlay to show the mitigations.

## 5. (Optional, moderate depth) Enable NetworkPolicy enforcement

The default EKS VPC CNI accepts NetworkPolicy objects but only **enforces** them when
network-policy support is turned on. Enable it on the add-on:

```bash
aws eks update-addon --cluster-name upwind-lab --addon-name vpc-cni \
  --configuration-values '{"enableNetworkPolicy":"true"}' \
  --resolve-conflicts OVERWRITE
```

(Alternatively install Calico.) Without this, the egress-blocked demo in the runbook
won't actually block — know this before you present.

## 6. Tear down

```bash
# Delete the Service first so its ELB is removed before the VPC is destroyed
kubectl delete -f k8s/juice-shop.yaml --ignore-not-found
kubectl delete -f k8s/hardened/juice-shop-hardened.yaml --ignore-not-found
cd terraform && terraform destroy
```

> If `terraform destroy` stalls on the VPC, it's almost always an orphaned ELB or
> leftover ENIs from a Service that wasn't deleted first. Delete the k8s Services, wait
> a minute, retry.

## Production upgrade paths (the "with more time" slide)
- **ALB Ingress + AWS WAF** via the AWS Load Balancer Controller (IRSA) instead of a
  Classic ELB — path routing, TLS, managed WAF rules.
- **Falco** DaemonSet + alerting for runtime detection (ties directly to Upwind's space).
- **IRSA / Pod Identity** for scoped pod permissions; **External Secrets** → AWS Secrets
  Manager; **image scanning** (ECR/Trivy) and **GitOps** (Argo CD) for the full pipeline.
