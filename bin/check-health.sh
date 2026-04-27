#!/bin/bash
# director maintainer health check — query all 5 agents' --version --json
# and emit a single combined JSON to stdout.
#
# Exit codes:
#   0 = all 5 agents healthy (or only degraded)
#   1 = any agent broken (exit 2)
#   2 = any agent missing/timeout (cannot reach)
#
# Usage:
#   bin/check-health.sh                  # JSON to stdout
#   bin/check-health.sh > .cache/health-$(date +%s).json

set -euo pipefail

# AGENT_NAME|HOW_TO_INVOKE_VERSION_JSON
AGENTS=(
  "script-gen|cd /home/myclaw/script-gen && uv run --quiet python -m cli.main --version --json"
  "picture-gen|python3 /home/myclaw/picture-gen/main.py --version --json"
  "audio-gen|/home/myclaw/audio-gen/.venv/bin/python3 /home/myclaw/audio-gen/generate.py --version --json"
  "bgm-gen|/home/myclaw/bgm-gen/.venv/bin/python3 /home/myclaw/bgm-gen/generate.py --version --json"
  "video-gen|python3 /home/myclaw/video-gen/scripts/health.py --version --json"
)

TIMEOUT=8  # seconds per agent
TS=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")

results="["
first=true
# overall: ok < degraded < broken < missing-or-error (precedence to worst)
overall="ok"
worst_exit=0

worst_set() {
  local new="$1" e="$2"
  case "$overall:$new" in
    ok:degraded|ok:broken|ok:missing-or-error|degraded:broken|degraded:missing-or-error|broken:missing-or-error)
      overall="$new" ;;
  esac
  [ "$e" -gt "$worst_exit" ] && worst_exit="$e"
}

for spec in "${AGENTS[@]}"; do
  name="${spec%%|*}"
  cmd="${spec#*|}"

  if $first; then first=false; else results+=","; fi

  if out=$(timeout "$TIMEOUT" bash -c "$cmd" 2>/dev/null); then
    code=$?
  else
    code=$?
  fi

  if [ -z "$out" ]; then
    case $code in
      124) status="timeout" ;;
      127) status="missing" ;;
      *)   status="error"   ;;
    esac
    results+=$(printf '{"name":"%s","status":"%s","exit_code":%d,"ts":"%s"}' \
                      "$name" "$status" "$code" "$TS")
    worst_set "missing-or-error" "$code"
    continue
  fi

  if ! echo "$out" | jq -e . >/dev/null 2>&1; then
    results+=$(printf '{"name":"%s","status":"legacy","exit_code":%d,"ts":"%s","raw":%s}' \
                      "$name" "$code" "$TS" "$(echo "$out" | head -1 | jq -Rs .)")
    worst_set "degraded" "$code"
    continue
  fi

  case $code in
    0) status="ok"       ;;
    1) status="degraded" ; worst_set "degraded" "$code" ;;
    2) status="broken"   ; worst_set "broken"   "$code" ;;
    *) status="error"    ; worst_set "missing-or-error" "$code" ;;
  esac
  results+=$(echo "$out" | jq --arg s "$status" --argjson c "$code" '. + {status:$s, exit_code:$c}')
done

results+="]"

echo "{\"director_check_ts\":\"$TS\",\"overall\":\"$overall\",\"agents\":$results}" | jq .

# Exit code: 0=ok, 1=degraded, 2=broken, 3=missing-or-error
case "$overall" in
  ok)                exit 0 ;;
  degraded)          exit 1 ;;
  broken)            exit 2 ;;
  missing-or-error)  exit 3 ;;
esac
