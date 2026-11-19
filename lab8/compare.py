#!/usr/bin/env python3
"""JSON vs Parquet: data scanned and run time of queries 3-5 (the table for the submission)."""
import json
import pathlib

res = pathlib.Path(__file__).resolve().parent / "results"
print(f"{'query':<18}{'JSON MB':>10}{'Parquet MB':>12}{'x cheaper':>11}{'JSON s':>9}{'Parquet s':>11}{'x faster':>10}")
for q in ("q3_turnover", "q4_failure_rate", "q5_peak_hours"):
    try:
        j = json.loads((res / f"{q}-json.stats.json").read_text())
        p = json.loads((res / f"{q}-parquet.stats.json").read_text())
    except FileNotFoundError:
        print(f"{q:<18}(missing: run part2.sh queries and part2.sh parquet first)")
        continue
    ratio = j["data_scanned_bytes"] / max(p["data_scanned_bytes"], 1)
    t = j["engine_ms"] / max(p["engine_ms"], 1)
    print(f"{q:<18}{j['data_scanned_mb']:>10}{p['data_scanned_mb']:>12}{ratio:>10.1f}x"
          f"{j['engine_ms'] / 1000:>9.1f}{p['engine_ms'] / 1000:>11.1f}{t:>9.1f}x")
