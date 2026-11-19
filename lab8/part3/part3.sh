#!/usr/bin/env bash
# Lab 8, Part 3: Redpanda + Python. Run one phase at a time, from the project root:
#   bash lab8/part3/part3.sh setup     venv, one day of data, Redpanda + Console, topic payments (3 partitions)
#   bash lab8/part3/part3.sh exp0      baseline: producer + consumer, lateness 120 s
#   bash lab8/part3/part3.sh exp1      stop the consumer for 60 s and start it again
#   bash lab8/part3/part3.sh exp2      two consumers in one group (open the Console first)
#   bash lab8/part3/part3.sh exp3      30% of payments fail: the alert fires
#   bash lab8/part3/part3.sh exp4      zero waiting time for late events
#   bash lab8/part3/part3.sh report    one table of all experiments
#   bash lab8/part3/part3.sh down      stop and remove the containers
# Every phase writes to lab8/part3/logs/ and lab8/part3/results/.
set -euo pipefail
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
cd "$(dirname "${SELF}")"

[ -n "${AWS_PROFILE-x}" ] || unset AWS_PROFILE
export AWS_REGION="${LAB8_REGION:-eu-north-1}" AWS_DEFAULT_REGION="${LAB8_REGION:-eu-north-1}"

DAY="${DAY:-2026-10-15}"            # which dt= partition to replay
RATE="${RATE:-20}"                  # events per second
FROM="${SLICE_FROM:-17:00}"         # replay only this slice of the day (receivedAt, UTC),
TO="${SLICE_TO:-17:30}"             # about 3 minutes at 20 events/s; use 00:00 / 24:00 for the whole day
PY=".venv/bin/python"
mkdir -p logs results data

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi
rpk() { ${DC} exec -T redpanda rpk "$@"; }

reset_topic() {
  rpk topic delete payments >/dev/null 2>&1 || true
  sleep 2
  rpk topic create payments -p 3 -r 1
}

produce_bg() {   # produce_bg NAME [extra producer args]; sets PROD
  local name="$1"; shift
  ${PY} producer.py --file data/day.jsonl --from "${FROM}" --to "${TO}" --rate "${RATE}" \
    --summary "results/${name}-producer.json" "$@" > "logs/${name}-producer.log" 2>&1 &
  PROD=$!
}

consume() {      # consume NAME [extra consumer args]  (foreground, log copied to the screen)
  local name="$1"; shift
  ${PY} consumer.py --group "g-${name}-$(date +%s)" --summary "results/${name}-consumer.json" "$@" 2>&1 \
    | tee "logs/${name}-consumer.log"
}

case "${1:-}" in
  setup)
    command -v docker >/dev/null || { echo "docker is not installed or not running"; exit 1; }
    python3 -m venv .venv
    .venv/bin/pip install -q --upgrade pip confluent-kafka
    ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
    if [ ! -s data/day.jsonl ]; then
      aws s3 cp "s3://spry-lab8-${ACCOUNT}/payments/dt=${DAY}/events.jsonl" data/day.jsonl --only-show-errors
    fi
    echo "day ${DAY}: $(wc -l < data/day.jsonl) events"
    ${DC} up -d
    echo "waiting for Redpanda..."
    for _ in $(seq 60); do rpk cluster info >/dev/null 2>&1 && break; sleep 2; done
    rpk topic create payments -p 3 -r 1 || true
    rpk topic describe payments | head -20
    echo "Console: http://localhost:8080  (Topics -> payments)"
    ;;
  exp0)
    reset_topic
    produce_bg exp0
    consume exp0 --lateness 120
    wait "${PROD}" || true
    cat logs/exp0-producer.log | tail -2
    ;;
  exp1)
    reset_topic
    produce_bg exp1
    G="g-exp1-$(date +%s)"
    ${PY} consumer.py --group "${G}" --idle-exit 0 --summary results/exp1a-consumer.json > logs/exp1a-consumer.log 2>&1 &
    A=$!
    sleep 40
    kill -TERM "${A}" || true
    wait "${A}" || true
    echo "consumer stopped after 40 s; the producer keeps writing; waiting 60 s"
    tail -3 logs/exp1a-consumer.log
    sleep 60
    echo "starting the consumer again with the same group"
    ${PY} consumer.py --group "${G}" --summary results/exp1b-consumer.json 2>&1 | tee logs/exp1b-consumer.log
    wait "${PROD}" || true
    ${PY} - <<'EOF'
import json
p = json.load(open("results/exp1-producer.json"))["produced"]
a = json.load(open("results/exp1a-consumer.json"))["consumed"]
b = json.load(open("results/exp1b-consumer.json"))["consumed"]
print(f"\nproduced {p}; consumer before the stop {a}; after the restart {b}; total {a + b}; lost {p - a - b}")
EOF
    ;;
  exp2)
    reset_topic
    produce_bg exp2
    G="g-exp2-$(date +%s)"
    ${PY} consumer.py --group "${G}" --idle-exit 25 --summary results/exp2-consumer1.json > logs/exp2-consumer1.log 2>&1 &
    C1=$!
    sleep 12
    echo "starting the second consumer: watch Consumer Groups in the Console (http://localhost:8080)"
    ${PY} consumer.py --group "${G}" --idle-exit 25 --summary results/exp2-consumer2.json > logs/exp2-consumer2.log 2>&1 &
    C2=$!
    sleep 20
    rpk group describe "${G}" | tee logs/exp2-group.txt
    wait "${C1}" "${C2}" "${PROD}" || true
    echo; echo "--- partition assignments ---"
    grep -H "assigned\|revoked" logs/exp2-consumer1.log logs/exp2-consumer2.log
    ;;
  exp3)
    reset_topic
    produce_bg exp3 --fail-pct 30
    consume exp3 --lateness 120
    wait "${PROD}" || true
    echo; grep -c ALERT logs/exp3-consumer.log | sed 's/^/alerts: /' || true
    ;;
  exp4)
    reset_topic
    produce_bg exp4
    consume exp4 --lateness 0
    wait "${PROD}" || true
    ;;
  report)
    ${PY} - <<'EOF'
import json, os
rows = []
for n in ["exp0", "exp1a", "exp1b", "exp2-consumer1", "exp2-consumer2", "exp3", "exp4"]:
    f = f"results/{n}-consumer.json" if os.path.exists(f"results/{n}-consumer.json") else f"results/{n}.json"
    if not os.path.exists(f):
        continue
    s = json.load(open(f))
    rows.append((n, s["lateness"], s["consumed"], s["duplicates"], s["late"], s["late_terminal"],
                 s["terminal_counted"], s["windows_closed"], s["alerts"]))
print(f"{'run':<16}{'lateness':>9}{'consumed':>9}{'dups':>6}{'late':>6}{'late_term':>10}{'counted':>8}{'windows':>8}{'alerts':>7}")
for r in rows:
    print(f"{r[0]:<16}{r[1]:>9}{r[2]:>9}{r[3]:>6}{r[4]:>6}{r[5]:>10}{r[6]:>8}{r[7]:>8}{r[8]:>7}")
EOF
    ;;
  down)
    ${DC} down
    ;;
  *)
    sed -n '2,12p' "${SELF}"; exit 2 ;;
esac
