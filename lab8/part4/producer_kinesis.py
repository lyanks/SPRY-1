#!/usr/bin/env python3
"""Replay one slice of the payments day into the Kinesis stream, like Part 3 did into Redpanda.

  python producer_kinesis.py --stream lab8-payments --from 17:00 --to 17:30 --rate 20 [--fail-pct 30]

The partition key is invoiceId (all events of a payment go to one shard, in order).
Every record ends with a newline: Firehose glues records together, and Athena reads JSON Lines.
"""
import argparse
import json
import time
import zlib

import boto3

TERMINAL = ("success", "failure")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stream", default="lab8-payments")
    ap.add_argument("--file", default="../part3/data/day.jsonl")
    ap.add_argument("--rate", type=float, default=20.0)
    ap.add_argument("--from", dest="t_from", default="17:00")
    ap.add_argument("--to", dest="t_to", default="17:30")
    ap.add_argument("--fail-pct", type=int, default=0)
    args = ap.parse_args()

    events = []
    with open(args.file, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                e = json.loads(line)
                if args.t_from <= e["receivedAt"][11:16] < args.t_to:
                    events.append(e)
    events.sort(key=lambda e: e["receivedAt"])
    if args.fail_pct:
        for e in events:
            if e["status"] in TERMINAL and zlib.crc32(e["invoiceId"].encode()) % 100 < args.fail_pct:
                e["status"], e["finalAmount"] = "failure", 0
                if not e.get("failureReason"):
                    e["failureReason"] = "Injected failure"
    print(f"{len(events)} events, {args.rate:g}/s, about {len(events) / args.rate:.0f} s", flush=True)

    kinesis = boto3.client("kinesis")
    step = max(1, int(args.rate))          # one PutRecords call per second
    start = time.monotonic()
    sent = failed = 0
    for i in range(0, len(events), step):
        delay = start + i / args.rate - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        batch = events[i:i + step]
        resp = kinesis.put_records(StreamName=args.stream, Records=[
            {"Data": (json.dumps(e, ensure_ascii=False) + "\n").encode(), "PartitionKey": e["invoiceId"]}
            for e in batch])
        sent += len(batch) - resp["FailedRecordCount"]
        failed += resp["FailedRecordCount"]
        if (i // step) % 25 == 24:
            print(f"  sent {sent}/{len(events)}", flush=True)
    print(f"done: {sent} records accepted by Kinesis, {failed} failed", flush=True)


if __name__ == "__main__":
    main()
