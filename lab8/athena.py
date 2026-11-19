#!/usr/bin/env python3
"""Run one Athena SQL file through the AWS CLI; print the rows, the data scanned and the run time.

  python3 athena.py sql/q3_turnover.sql -D TABLE=payments
  python3 athena.py sql/q3_turnover.sql -D TABLE=payments_parquet --label parquet

${BUCKET} comes from the environment, any other ${NAME} from -D NAME=value.
Results are saved to results/<file>[-label].csv and results/<file>[-label].stats.json
(the figures the lab asks for: Data scanned, run time).
"""
import argparse
import csv
import json
import os
import pathlib
import subprocess
import sys
import time


def aws(*args):
    out = subprocess.run(["aws", *args, "--output", "json"], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"aws {' '.join(args[:2])} failed:\n{out.stderr.strip()}")
    return json.loads(out.stdout) if out.stdout.strip() else {}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("sql_file")
    p.add_argument("-D", action="append", default=[], metavar="NAME=value")
    p.add_argument("--database", default="lab8")
    p.add_argument("--workgroup", default="primary")
    p.add_argument("--label", default="")
    args = p.parse_args()

    values = {"BUCKET": os.environ.get("BUCKET", "")}
    for item in args.D:
        k, _, v = item.partition("=")
        values[k] = v
    sql = pathlib.Path(args.sql_file).read_text()
    for k, v in values.items():
        sql = sql.replace("${" + k + "}", v)
    if "${" in sql:
        sys.exit(f"unresolved placeholder in {args.sql_file}: pass it with -D NAME=value")
    if not values["BUCKET"] and "s3://" in sql:
        sys.exit("BUCKET is not set")

    out_loc = f"s3://{values['BUCKET']}/athena-results/"
    start = aws(
        "athena", "start-query-execution", "--query-string", sql,
        "--query-execution-context", f"Database={args.database}",
        "--result-configuration", f"OutputLocation={out_loc}",
        "--work-group", args.workgroup,
    )
    qid = start["QueryExecutionId"]
    name = pathlib.Path(args.sql_file).stem + (f"-{args.label}" if args.label else "")
    print(f"== {name}  ({qid})")

    while True:
        ex = aws("athena", "get-query-execution", "--query-execution-id", qid)["QueryExecution"]
        state = ex["Status"]["State"]
        if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break
        time.sleep(1.5)
    if state != "SUCCEEDED":
        sys.exit(f"{state}: {ex['Status'].get('StateChangeReason', '')}")

    stats = ex.get("Statistics", {})
    scanned = stats.get("DataScannedInBytes", 0)
    summary = {
        "query": name,
        "data_scanned_bytes": scanned,
        "data_scanned_mb": round(scanned / 1024 / 1024, 2),
        "engine_ms": stats.get("EngineExecutionTimeInMillis"),
        "total_ms": stats.get("TotalExecutionTimeInMillis"),
    }

    rows = []
    if ex.get("StatementType") == "DML":
        res = aws("athena", "get-query-results", "--query-execution-id", qid)
        for r in res["ResultSet"]["Rows"]:
            rows.append([c.get("VarCharValue", "") for c in r["Data"]])

    if rows:
        widths = [max(len(str(r[i])) for r in rows[:60]) for i in range(len(rows[0]))]
        for r in rows[:60]:
            print("  " + "  ".join(str(v).ljust(w) for v, w in zip(r, widths)))
        if len(rows) > 60:
            print(f"  ... {len(rows) - 1} rows in total (all of them are in the CSV)")

    results = pathlib.Path(__file__).resolve().parent / "results"
    results.mkdir(exist_ok=True)
    if rows:
        with open(results / f"{name}.csv", "w", newline="") as f:
            csv.writer(f).writerows(rows)
    (results / f"{name}.stats.json").write_text(json.dumps(summary, indent=2))
    print(f"  data scanned: {summary['data_scanned_mb']} MB   engine time: {summary['engine_ms']} ms   total: {summary['total_ms']} ms")


if __name__ == "__main__":
    main()
