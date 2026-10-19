"""`make parse TEXT="..."`: run the parser from a laptop and print the JSON and the usage."""

import argparse
import json
import sys
import time
from datetime import datetime
from zoneinfo import ZoneInfo

from app.ai.agenda import PROMPT_VERSION, ParserConfig, cost_usd, parse_agenda


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Parse pasted text into a meeting agenda.")
    ap.add_argument("text", nargs="?", help="the text; read from stdin when omitted")
    ap.add_argument("--tz", default="Europe/Kyiv")
    args = ap.parse_args(argv)

    text = args.text if args.text is not None else sys.stdin.read()
    config = ParserConfig.from_env()
    today = datetime.now(ZoneInfo(args.tz)).date()

    started = time.monotonic()
    agenda, usage = parse_agenda(text, today, args.tz, config=config)
    print(agenda.model_dump_json(indent=2))
    print(
        json.dumps(
            {
                "model": config.model,
                "prompt_version": PROMPT_VERSION,
                **usage,
                "latency_ms": int((time.monotonic() - started) * 1000),
                "cost_usd": cost_usd(config.model, usage),
            }
        ),
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
