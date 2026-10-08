# Presentation Outline (30–45 min)

Target: ~15 slides + ~15 min of live demo. Keep slides sparse; let the demo carry it.

| # | Slide | Time | Notes / talk track |
|---|-------|------|--------------------|
| 1 | Title | 0:30 | Name, role, "Kubernetes security lab on AWS EKS" |
| 2 | Agenda | 0:30 | Architecture → exploits → hardening → IR |
| 3 | Goals & scope | 1:00 | Restate the assignment in your words; what "done" means |
| 4 | **Architecture diagram** | 3:00 | The Mermaid topology from `architecture.md`; walk the request path |
| 5 | Design choices & tradeoffs | 3:00 | EKS vs self-managed, Terraform vs eksctl, private nodes, ELB vs ALB |
| 6 | How it's built (IaC) | 2:00 | One glance at Terraform; "terraform apply → kubectl → kubectl apply" |
| 7 | Threat framing | 1:30 | OWASP Top 10; why I picked these 3 categories |
| 8 | **DEMO: Injection (A03)** | 4:00 | Live SQLi auth bypass; show browser + curl |
| 9 | Injection — root cause & fixes | 2:00 | Parameterized queries; WAF; detection signals |
| 10 | **DEMO: Broken Access Control (A01)** | 4:00 | Live IDOR basket access |
| 11 | BAC — root cause & fixes | 2:00 | Object-level authz; honest "k8s can't fix logic" point |
| 12 | **DEMO: Security Misconfig (A05)** | 3:00 | Leaked file + admin surface |
| 13 | Misconfig — root cause & fixes | 2:00 | Bridge to k8s hardening |
| 14 | **DEMO: Hardening in action** | 4:00 | Apply overlay; show egress blocked by NetworkPolicy |
| 15 | Defense-in-depth summary | 2:00 | App / k8s / detection table across all 3 |
| 16 | Extra credit: IR walkthrough | 3:00 | Detect→triage→contain→eradicate→recover→learn |
| 17 | What I'd do with more time | 1:00 | Falco+alerting, ALB+WAF, IRSA, image scanning, GitOps |
| 18 | Q&A | — | |

## Defense-in-depth summary slide (table to put on slide 15)

| Vuln | App-level fix | Kubernetes / infra control | Detection |
|------|---------------|----------------------------|-----------|
| A03 Injection | Parameterized queries, input validation, least-priv DB user | WAF (ALB+AWS WAF), NetworkPolicy egress limits | WAF SQLi hits, DB audit logs, anomalous egress |
| A01 Broken Access Control | Per-object ownership checks, UUIDs | Rate-limit/WAF, audit logging (can't fix logic) | Sequential id enumeration per token |
| A05 Misconfig | `NODE_ENV=production`, remove sample files, gate admin | PSA restricted, non-root, read-only FS, drop caps, NetworkPolicy | Requests to sensitive paths, Falco shell-in-container |

## Delivery tips
- Pre-pull the Juice Shop image and pre-provision the LB so nothing is "waiting" on stage.
- Have the exploits scripted in `runbook.md` so a flubbed keystroke doesn't derail you.
- Record a 2-min backup screen capture of each exploit in case live networking fails.
- Time-box Q&A; keep the "with more time" slide as a pressure-release for gaps.
