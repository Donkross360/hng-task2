## Observability & Alerts Runbook

This system posts Slack alerts based on Nginx access logs. Alerts are produced by a lightweight Python watcher that tails `/var/log/nginx/access.json`.

### Alert Types

- Failover Detected (Blue → Green or Green → Blue)
  - Meaning: The active upstream pool flipped. Nginx started serving from the backup.
  - Likely causes: Health issues with the primary (timeouts, 5xx), planned maintenance.
  - Operator actions:
    1. Inspect primary container logs (`docker-compose logs app-blue|app-green`).
    2. Check health endpoints and latency.
    3. If degradation persists, keep traffic on the healthy pool and investigate root cause.

- High Error Rate (> threshold over window)
  - Meaning: Upstream 5xx proportion exceeded configured threshold over the sliding window.
  - Operator actions:
    1. Review upstream app logs for recent exceptions.
    2. Validate dependencies (DB, cache, upstream services).
    3. Consider toggling pools or enabling maintenance mode if needed.

- Recovery (implicit)
  - When pool flips back to the primary, a new failover alert is sent indicating recovery.

### Maintenance Mode

Set `MAINTENANCE_MODE=true` in the environment (and restart watcher) to suppress alerts during planned pool toggles or maintenance windows. Metrics are still computed; alerts are not sent.

### Configuration

- SLACK_WEBHOOK_URL — Slack Incoming Webhook URL.
- ERROR_RATE_THRESHOLD — percentage; default 2.
- WINDOW_SIZE — sliding window size; default 200 requests.
- ALERT_COOLDOWN_SEC — seconds between alerts of same type; default 300.
- ACTIVE_POOL — initial pool assumption for failover detection.

### Troubleshooting

- No alerts in Slack:
  - Verify `SLACK_WEBHOOK_URL` is set and correct.
  - Ensure the watcher is running (`docker-compose logs alert_watcher`).
  - Confirm Nginx writes logs to `/var/log/nginx/access.json`.

- Too many alerts:
  - Increase `ALERT_COOLDOWN_SEC`.
  - Raise `ERROR_RATE_THRESHOLD` or `WINDOW_SIZE`.

- False failovers:
  - Verify the app sets `X-App-Pool` and `X-Release-Id` correctly.
  - Check Nginx upstream health and timeouts.


