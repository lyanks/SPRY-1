#!/usr/bin/env python3
"""Read `payments`, drop duplicates, and compute the share of failed payments per paymentMethod
in 1-minute windows of EVENT time (modifiedDate). Print an alert when the share is above 10%.

A window [s, s+60) is closed when the watermark (the largest modifiedDate seen so far) reaches
s + 60 + --lateness (default 120 s). An event for an already closed window is rejected as late.

  python consumer.py --group g1
  python consumer.py --group g1 --lateness 0        # experiment 4
"""
import argparse
import json
import signal
import sys
import time
from datetime import datetime, timezone

TERMINAL = ("success", "failure")


def to_epoch(s):
    return int(datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())


def hhmm(t):
    return datetime.fromtimestamp(t, timezone.utc).strftime("%H:%M:%S")


class Windower:
    """The stream logic, without Kafka, so it can be tested on its own."""

    def __init__(self, window=60, lateness=120, threshold=0.10, min_count=10, emit=print):
        self.window, self.lateness = window, lateness
        self.threshold, self.min_count = threshold, min_count
        self.emit = emit
        self.seen = set()        # (invoiceId, status); grows without limit: see the lab text
        self.open = {}           # (window_start, method) -> [terminal payments, failed]
        self.watermark = 0
        self.closed = []         # records of closed windows
        self.stats = dict(consumed=0, duplicates=0, late=0, late_terminal=0, terminal_counted=0, alerts=0)

    def feed(self, e):
        st = self.stats
        st["consumed"] += 1
        key = (e["invoiceId"], e["status"])
        if key in self.seen:
            st["duplicates"] += 1
            return
        self.seen.add(key)

        t = to_epoch(e["modifiedDate"])
        start = t - t % self.window
        terminal = e["status"] in TERMINAL
        if self.watermark >= start + self.window + self.lateness:
            st["late"] += 1
            if terminal:
                st["late_terminal"] += 1
            return
        if terminal:
            w = self.open.setdefault((start, e["paymentMethod"]), [0, 0])
            w[0] += 1
            w[1] += e["status"] == "failure"
            st["terminal_counted"] += 1
        if t > self.watermark:
            self.watermark = t
            self._close(final=False)

    def _close(self, final):
        done = [k for k in self.open if final or k[0] + self.window + self.lateness <= self.watermark]
        for k in sorted(done):
            total, failed = self.open.pop(k)
            share = failed / total
            alert = total >= self.min_count and share > self.threshold
            self.stats["alerts"] += alert
            self.closed.append(dict(window=hhmm(k[0]), method=k[1], payments=total, failed=failed,
                                    share=round(share * 100, 1), alert=alert, final_flush=final))
            self.emit(f"window {hhmm(k[0])}  {k[1]:<10} payments={total:<4} failed={failed:<3} "
                      f"share={share * 100:5.1f}%" + ("   ALERT: failure share above "
                      f"{self.threshold * 100:.0f}%" if alert else "") + ("   (final flush)" if final else ""))

    def flush(self):
        self._close(final=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bootstrap", default="localhost:19092")
    ap.add_argument("--topic", default="payments")
    ap.add_argument("--group", required=True)
    ap.add_argument("--lateness", type=int, default=120, help="seconds to wait for late events")
    ap.add_argument("--threshold", type=float, default=0.10)
    ap.add_argument("--min-count", type=int, default=10, help="no alert for windows with fewer payments")
    ap.add_argument("--idle-exit", type=int, default=20, help="stop after this many seconds without messages (0 = never)")
    ap.add_argument("--summary", default=None)
    args = ap.parse_args()

    from confluent_kafka import Consumer

    stop = []
    signal.signal(signal.SIGINT, lambda *a: stop.append(1))
    signal.signal(signal.SIGTERM, lambda *a: stop.append(1))

    def on_assign(c, parts):
        print(f"assigned partitions {sorted(p.partition for p in parts)}", flush=True)

    def on_revoke(c, parts):
        print(f"revoked partitions {sorted(p.partition for p in parts)}", flush=True)

    c = Consumer({"bootstrap.servers": args.bootstrap, "group.id": args.group,
                  "auto.offset.reset": "earliest", "enable.auto.commit": False})
    c.subscribe([args.topic], on_assign=on_assign, on_revoke=on_revoke)

    w = Windower(lateness=args.lateness, threshold=args.threshold, min_count=args.min_count,
                 emit=lambda s: print(s, flush=True))
    print(f"consumer group={args.group} lateness={args.lateness}s threshold={args.threshold * 100:.0f}%", flush=True)

    last = time.monotonic()
    since_commit = 0
    try:
        while not stop:
            m = c.poll(1.0)
            if m is None:
                if args.idle_exit and time.monotonic() - last > args.idle_exit:
                    print(f"no messages for {args.idle_exit} s, stopping", flush=True)
                    break
                continue
            if m.error():
                print("kafka error:", m.error(), file=sys.stderr, flush=True)
                continue
            last = time.monotonic()
            w.feed(json.loads(m.value()))
            since_commit += 1
            if since_commit >= 200:
                c.commit(asynchronous=False)
                since_commit = 0
    finally:
        try:
            c.commit(asynchronous=False)
        except Exception:
            pass
        c.close()

    w.flush()
    s = dict(w.stats, seen_set_size=len(w.seen), windows_closed=len(w.closed), lateness=args.lateness,
             group=args.group)
    print("summary:", json.dumps(s), flush=True)
    if args.summary:
        with open(args.summary, "w") as f:
            json.dump(dict(s, windows=w.closed), f, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    main()
