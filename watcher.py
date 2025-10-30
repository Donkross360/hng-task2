import json
import os
import time
from collections import deque
from datetime import datetime, timezone
from typing import Deque, Dict, Any, Optional

import requests


LOG_PATH = os.environ.get("NGINX_LOG_FILE", "/var/log/nginx/access.json")
SLACK_WEBHOOK_URL = os.environ.get("SLACK_WEBHOOK_URL", "")
SLACK_PREFIX = os.environ.get("SLACK_PREFIX", "from: @Techalla")
ACTIVE_POOL = os.environ.get("ACTIVE_POOL", "blue")
ERROR_RATE_THRESHOLD = float(os.environ.get("ERROR_RATE_THRESHOLD", "2"))
WINDOW_SIZE = int(os.environ.get("WINDOW_SIZE", "200"))
ALERT_COOLDOWN_SEC = int(os.environ.get("ALERT_COOLDOWN_SEC", "300"))
MAINTENANCE_MODE = os.environ.get("MAINTENANCE_MODE", "false").lower() == "true"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def post_to_slack(text: str) -> None:
    if not SLACK_WEBHOOK_URL:
        return
    try:
        resp = requests.post(
            SLACK_WEBHOOK_URL,
            json={"text": f"{SLACK_PREFIX} | {text}"},
            timeout=5,
        )
        resp.raise_for_status()
    except Exception:
        pass


def parse_log_line(line: str) -> Optional[Dict[str, Any]]:
    line = line.strip()
    if not line:
        return None
    try:
        data = json.loads(line)
        return {
            "pool": data.get("pool"),
            "release": data.get("release"),
            "status": int(data.get("status")) if data.get("status") is not None else None,
            "upstream_status": str(data.get("upstream_status")) if data.get("upstream_status") is not None else None,
            "upstream_addr": data.get("upstream_addr"),
            "request_time": float(data.get("request_time")) if data.get("request_time") is not None else None,
            "upstream_response_time": data.get("upstream_response_time"),
            "time": data.get("time"),
        }
    except Exception:
        return None


class AlertState:
    def __init__(self) -> None:
        self.last_pool: Optional[str] = ACTIVE_POOL
        self.window: Deque[Dict[str, Any]] = deque(maxlen=WINDOW_SIZE)
        self.cooldowns: Dict[str, float] = {}

    def _cooldown_ok(self, key: str) -> bool:
        last = self.cooldowns.get(key)
        now = time.time()
        if last is None or (now - last) >= ALERT_COOLDOWN_SEC:
            self.cooldowns[key] = now
            return True
        return False

    def error_rate_pct(self) -> float:
        if not self.window:
            return 0.0
        total = len(self.window)
        err = 0
        for item in self.window:
            upstream_status = item.get("upstream_status") or ""
            if any(s.startswith("5") for s in upstream_status.split(",") if s):
                err += 1
            elif item.get("status") and 500 <= int(item["status"]) <= 599:
                err += 1
        return (err / total) * 100.0

    def handle_event(self, evt: Dict[str, Any]) -> None:
        pool = evt.get("pool")
        release = evt.get("release")
        upstream_addr = evt.get("upstream_addr")

        self.window.append(evt)

        if MAINTENANCE_MODE:
            return

        if pool and self.last_pool and pool != self.last_pool:
            if self._cooldown_ok(f"failover_to_{pool}"):
                rate = self.error_rate_pct()
                post_to_slack(
                    f"*Failover Detected*: {self.last_pool} → {pool}\n"
                    f"• time: {now_iso()}\n"
                    f"• error_rate({len(self.window)}): {rate:.2f}%\n"
                    f"• release: {release}\n"
                    f"• upstream: {upstream_addr}\n"
                    f"Action: Check health of {self.last_pool} and upstream logs."
                )
            self.last_pool = pool

        if len(self.window) >= max(50, int(WINDOW_SIZE * 0.5)):
            rate = self.error_rate_pct()
            if rate > ERROR_RATE_THRESHOLD:
                band = int(round(rate))
                if self._cooldown_ok(f"error_rate_{band}"):
                    post_to_slack(
                        f"*High Error Rate*: {rate:.2f}% over last {len(self.window)} requests\n"
                        f"• time: {now_iso()}\n"
                        f"• active_pool: {pool or self.last_pool}\n"
                        f"• release: {release}\n"
                        f"Action: Inspect upstream errors, consider toggling pools."
                    )


def tail_file(path: str):
    with open(path, "r") as f:
        f.seek(0, os.SEEK_END)
        while True:
            line = f.readline()
            if not line:
                time.sleep(0.2)
                continue
            yield line


def main() -> None:
    state = AlertState()
    while not os.path.exists(LOG_PATH):
        time.sleep(0.5)
    for line in tail_file(LOG_PATH):
        evt = parse_log_line(line)
        if evt is None:
            continue
        state.handle_event(evt)


if __name__ == "__main__":
    main()


