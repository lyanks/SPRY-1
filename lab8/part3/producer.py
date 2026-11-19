#!/usr/bin/env python3
"""Replay one day of payment events into the Kafka topic `payments`.

Events are sent in the order of receivedAt (processing time), about --rate events a second,
so late events really do arrive late. The message key is invoiceId: all events of one payment
land in one partition, in order.

  python producer.py --file data/day.jsonl --from 17:00 --to 17:30 --rate 20
  python producer.py ... --fail-pct 30     # make about 30% of payments fail (experiment 3)
"""
import argparse
import json
import time
import zlib

from confluent_kafka import Producer

TERMINAL = ("success", "failure")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default="data/day.jsonl")
    ap.add_argument("--bootstrap", default="localhost:19092")
    ap.add_argument("--topic", default="payments")
    ap.add_argument("--rate", type=float, default=20.0, help="events per second")
    ap.add_argument("--from", dest="t_from", default="00:00", help="receivedAt, HH:MM (UTC), inclusive")
    ap.add_argument("--to", dest="t_to", default="24:00", help="receivedAt, HH:MM (UTC), exclusive")
    ap.add_argument("--fail-pct", type=int, default=0, help="make this percent of payments fail")
    ap.add_argument("--summary", default=None, help="write a JSON summary here")
    args = ap.parse_args()

    events = []
    with open(args.file, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            e = json.loads(line)
            if args.t_from <= e["receivedAt"][11:16] < args.t_to:
                events.append(e)
    events.sort(key=lambda e: e["receivedAt"])

    injected = 0
    if args.fail_pct:
        # The same payments fail every run: the choice depends only on invoiceId.
        for e in events:
            if e["status"] in TERMINAL and zlib.crc32(e["invoiceId"].encode()) % 100 < args.fail_pct:
                if e["status"] != "failure":
                    injected += 1
                e["status"] = "failure"
                e["finalAmount"] = 0
                e.setdefault("failureReason", "Injected failure")
                if not e.get("failureReason"):
                    e["failureReason"] = "Injected failure"

    print(f"{len(events)} events, receivedAt {args.t_from}..{args.t_to}, "
          f"{args.rate:g}/s, about {len(events) / args.rate:.0f} s, fail-pct {args.fail_pct}", flush=True)

    p = Producer({"bootstrap.servers": args.bootstrap, "linger.ms": 5})
    errors = []

    def on_delivery(err, msg):
        if err is not None:
            errors.append(str(err))

    start = time.monotonic()
    for i, e in enumerate(events):
        target = start + i / args.rate
        delay = target - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        p.produce(args.topic, key=e["invoiceId"], value=json.dumps(e, ensure_ascii=False), on_delivery=on_delivery)
        p.poll(0)
        if (i + 1) % 500 == 0:
            print(f"  sent {i + 1}/{len(events)}", flush=True)
    p.flush()
    seconds = time.monotonic() - start
    print(f"done: produced {len(events)} events in {seconds:.0f} s, {len(errors)} delivery errors", flush=True)

    if args.summary:
        with open(args.summary, "w") as f:
            json.dump({"produced": len(events), "seconds": round(seconds, 1), "rate": args.rate,
                       "fail_pct": args.fail_pct, "injected_failures": injected,
                       "delivery_errors": len(errors), "slice": [args.t_from, args.t_to]}, f, indent=2)


if __name__ == "__main__":
    main()
