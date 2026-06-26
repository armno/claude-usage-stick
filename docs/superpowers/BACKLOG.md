# Backlog

Ideas deferred, not dropped. Most surfaced during the 2026-06-25 brainstorm that produced
[`specs/2026-06-25-paged-ui-alerts-design.md`](specs/2026-06-25-paged-ui-alerts-design.md).
Board scope is T-Display S3 (Mango) unless noted.

## Deferred from the paged-UI + alerts spec

- **Burn-rate / time-to-cap projection page** — "5h cap in ~47m at this pace." The history
  ring buffer (Phase 3) already holds the samples needed to compute it; this is a natural
  follow-on page once history lands.
- **7d usage-history sparkline** — the spec keeps only a 7d trend arrow. A real 7d sparkline
  needs a second, coarsely-decimated ring buffer (~1 sample / 15 min over several days).
- **Runtime config in the setup portal** — surface the alert thresholds (now hardcoded 50/80)
  and the timezone (now hardcoded UTC+7) as portal fields instead of `config.h` constants.
- **Auto-rotating / hybrid navigation** — pages cycle on their own every N seconds; A pauses.
  Manual paging was chosen for v2.2.0; revisit if hands-free desk viewing is wanted.
- **Idle auto-return to Usage** — after N minutes idle, snap back to page 0. Chosen behavior
  is to stay put.

## Broader ideas (brainstorm directions not taken)

- **Integrations / data out** — expose the current numbers on the LAN as JSON/HTML (curl it,
  wall display, Grafana), or publish to MQTT / Home Assistant (e.g. turn a lamp red at 90%).
  Reuses the existing network + web-server stack.
- **Precise status-incident parsing** — `status.cpp` currently does a crude substring scan
  (`"opus"` matches anywhere in any incident → false positives). Parse the incident
  components/names properly; optionally surface scheduled maintenance and overall status.
- **Finish the XS and XL display tiers** — tiny OLED (≤128×64) and big/touch (≥480×320) are
  still pending in the README roadmap.
- **Multiple tokens / accounts** — cycle between work and personal Claude accounts.
