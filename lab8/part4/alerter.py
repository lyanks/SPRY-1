#!/usr/bin/env python3
"""The 'Flink' box of the diagram, in small: read the Kinesis stream, compute the failure share per
payment method in 1-minute event-time windows (the same Windower as in Part 3), and publish every
alert to an SNS topic.

  python alerter.py --stream lab8-payments --topic-arn arn:aws:sns:...
"""
import argparse
import json
import pathlib
import sys
import time

import boto3

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "part3"))
from consumer import Windower  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stream", default="lab8-payments")
    ap.add_argument("--topic-arn", required=True)
    ap.add_argument("--lateness", type=int, default=120)
    ap.add_argument("--idle-exit", type=int, default=30)
    args = ap.parse_args()

    kinesis, sns = boto3.client("kinesis"), boto3.client("sns")
    published = [0]

    def emit(line):
        print(line, flush=True)
        if "ALERT" in line:
            sns.publish(TopicArn=args.topic_arn, Subject="Payment failure alert", Message=line)
            published[0] += 1

    w = Windower(lateness=args.lateness, emit=emit)
    shards = kinesis.list_shards(StreamName=args.stream)["Shards"]
    iters = {s["ShardId"]: kinesis.get_shard_iterator(StreamName=args.stream, ShardId=s["ShardId"],
                                                      ShardIteratorType="TRIM_HORIZON")["ShardIterator"]
             for s in shards}
    last = time.monotonic()
    while time.monotonic() - last < args.idle_exit:
        got = 0
        for sid, it in list(iters.items()):
            r = kinesis.get_records(ShardIterator=it, Limit=1000)
            iters[sid] = r["NextShardIterator"]
            for rec in r["Records"]:
                w.feed(json.loads(rec["Data"]))
                got += 1
        if got:
            last = time.monotonic()
        else:
            time.sleep(1)
    w.flush()
    print("summary:", json.dumps(dict(w.stats, sns_messages_published=published[0])), flush=True)


if __name__ == "__main__":
    main()
