#!/usr/bin/env bash
# Runs gate.sh against static fixture APIs: a healthy rollout must pass, a rolled-back one must fail.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); port=18765
run() { # run <fixture> -> exit code of the gate
  (cd "$here/fixtures/$1" && exec python3 -m http.server "$port" >/dev/null 2>&1) & local pid=$!
  for _ in $(seq 50); do curl -s "http://127.0.0.1:$port/" >/dev/null && break; sleep 0.1; done
  local rc=0
  LC_API_URL="http://127.0.0.1:$port" LC_API_KEY=k LC_PROJECT_ID=p GATE_CHECK=rollout GATE_TARGET=new-checkout \
    GATE_ALLOW_MISSING=false GITHUB_OUTPUT=/dev/null bash "$here/../gate.sh" || rc=$?
  kill "$pid"; wait "$pid" 2>/dev/null || true
  return "$rc"
}
run ok || { echo "healthy rollout failed the gate"; exit 1; }
if run bad; then echo "rolled-back rollout passed the gate"; exit 1; fi
echo "gate tests passed"
