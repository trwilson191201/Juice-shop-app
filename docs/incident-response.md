# Extra Credit — Production Incident Response Walkthrough

Scenario: **the SQL injection auth bypass (A03) is found being exploited in
production.** Here's how I'd respond, mapped to the NIST IR lifecycle.

## 1. Detection & identification
- Trigger: WAF SQLi rule firing at volume, auth-success anomalies from a single
  source, or an alert on unexpected egress from the app pod.
- Confirm scope: which service, which version, is the DB account read-only or read-write,
  what data is reachable from that account.
- Declare an incident, assign an incident commander, open a comms channel + timeline doc.

## 2. Triage & severity
- Classify by data exposure and blast radius: did they just authenticate, or dump tables?
- Check for signs of chaining (did the foothold reach the admin surface or the node?).
- Set severity (e.g. Sev-1 if PII/credentials exfiltrated) which drives who gets paged.

## 3. Containment (stop the bleeding, preserve evidence)
- **Short-term:** deploy/enable the WAF rule to block the payload pattern; rate-limit or
  block the source; if needed, scale the vulnerable Deployment down or cordon it.
- **Isolate, don't kill blindly:** apply a `default-deny` NetworkPolicy to the namespace
  so the pod can't exfiltrate or reach lateral targets, while keeping it up for forensics.
- **Preserve:** snapshot the pod (logs, `kubectl debug` / ephemeral container, capture
  the node if host compromise suspected) before replacing it.
- **Rotate:** DB credentials, JWT signing secret, any keys the pod could read.

## 4. Eradication
- Ship the real fix: parameterized queries; redeploy a patched image.
- Remove any attacker persistence (rogue accounts created via admin access, altered data).
- Re-point the DB app user to least privilege; confirm no leftover debug/`unsafe` flags.

## 5. Recovery
- Roll out the patched version behind the WAF; monitor closely for recurrence.
- Validate data integrity; restore from known-good backups if records were tampered.
- Lift temporary containment (NetworkPolicy/rate-limits) once stable.

## 6. Post-incident / lessons learned
- Blameless postmortem: timeline, root cause, what detection worked / was missing.
- Action items: SAST/DAST in CI to catch injection pre-prod, WAF by default, DB audit
  logging, runtime detection (Falco) with alerting, NetworkPolicy as standard baseline.
- Feed detections back as permanent rules so the same class is caught earlier next time.

## The one-liner for the panel
> "The app bug was the entry, but the reason it was only an incident and not a breach
> is that runtime controls — egress policy, least privilege, detection — capped the
> blast radius and gave us evidence. Fix the code, but assume the next bug and
> constrain + watch at runtime."
