#!/usr/bin/env bash
# Lucida release gate: mirrors `lucida rollout check` / `lucida experiments check` (go/cmd/lucida/cli_gate.go).
set -uo pipefail
base="${LC_API_URL%/}/v1/projects/${LC_PROJECT_ID}"
api() { # GET <path> [query]; prints body, returns 1 on HTTP >= 400 and sets $status
  local out; out=$(curl -sSL -w '\n%{http_code}' -H "Authorization: Bearer ${LC_API_KEY}" "${base}$1${2:+?$2}") || return 2
  status="${out##*$'\n'}"; body="${out%$'\n'*}"; printf '%s' "$body"; [ "$status" -lt 400 ]
}
all() { # all <path>: every row of a cursor-paged list, as one JSON array
  local cursor="" rows="[]" page
  while :; do
    page=$(api "$1" "limit=200${cursor:+&cursor=$cursor}") || { echo "::error::GET $1 failed (HTTP $status)" >&2; exit 2; }
    rows=$(jq -c --argjson r "$rows" '$r + .data' <<<"$page")
    cursor=$(jq -r '.next_cursor // empty' <<<"$page"); [ -n "$cursor" ] || break
  done
  printf '%s' "$rows"
}
checks="[]"
add() { checks=$(jq -c --arg n "$1" --argjson p "$2" --arg d "${3:-}" '. + [{name:$n, passed:$p, detail:$d}]' <<<"$checks"); }

case "$GATE_CHECK" in
  rollout)
    flag=$(all /flags | jq -c --arg t "$GATE_TARGET" 'map(select(.key==$t or .id==$t)) | first // empty')
    [ -n "$flag" ] || { echo "::error::flag $GATE_TARGET not found"; exit 2; }
    id=$(jq -r .id <<<"$flag"); kind=rollout; target=$(jq -r .key <<<"$flag"); st=""
    if ro=$(api "/flags/$id/guarded-rollout"); then
      st=$(jq -r '.status // ""' <<<"$ro")
      add not_rolled_back "$(jq '.status != "rolled_back" and .status != "aborted"' <<<"$ro")" "status $st"
      add no_guardrail_breach "$(jq '.breach == null' <<<"$ro")" "$(jq -c '.breach // empty' <<<"$ro")"
      add no_unacknowledged_notice "$(jq '.notice == null' <<<"$ro")" "$(jq -c '.notice // empty' <<<"$ro")"
    elif [ "$status" = 404 ]; then
      add rollout_exists "$([ "$GATE_ALLOW_MISSING" = true ] && echo true || echo false)" "the flag has no guarded rollout"
    else echo "::error::guarded-rollout read failed (HTTP $status)"; exit 2; fi ;;
  experiments)
    e=$(all /experiments | jq -c --arg t "$GATE_TARGET" 'map(select(.id==$t or .name==$t)) | first // empty')
    [ -n "$e" ] || { echo "::error::experiment $GATE_TARGET not found"; exit 2; }
    id=$(jq -r .id <<<"$e"); kind=experiment; target=$(jq -r .name <<<"$e"); st=$(jq -r '.status // ""' <<<"$e")
    if res=$(api "/experiments/$id/results"); then
      add results_available true
      add no_sample_ratio_mismatch "$(jq '(.srm.flagged // false) | not' <<<"$res")" "$(jq -r '.srm.p_value // empty | "p=\(.)"' <<<"$res")"
      add no_guardrail_breach "$(jq '(.guardrail_breached // false) | not' <<<"$res")"
      add healthy_exposure "$(jq '(.exposure_health.flagged // false) | not' <<<"$res")"
      if chk=$(api "/experiments/$id/checks"); then
        add no_pre_exposure_bias "$(jq '(.biased // false) | not' <<<"$chk")"
        if [ "$(jq '.aa != null' <<<"$chk")" = true ]; then add aa_test_passed "$(jq '.aa.passed' <<<"$chk")" "$(jq -r '.aa.significant // [] | join(", ")' <<<"$chk")"; fi
      else add health_checks_available false "HTTP $status"; fi
    else add results_available false "HTTP $status"; fi ;;
  *) echo "::error::check must be rollout or experiments (got $GATE_CHECK)"; exit 2 ;;
esac

passed=$(jq 'all(.passed)' <<<"$checks")
report=$(jq -nc --arg k "$kind" --arg t "$target" --arg i "$id" --arg s "$st" --argjson c "$checks" --argjson p "$passed" \
  '{kind:$k, target:$t, id:$i, status:$s, passed:$p, checks:$c}')
echo "$report"
{ echo "passed=$passed"; echo "report<<LUCIDA_GATE_EOF"; echo "$report"; echo "LUCIDA_GATE_EOF"; } >> "${GITHUB_OUTPUT:-/dev/null}"
[ "$passed" = true ] || { echo "::error::Lucida $GATE_CHECK check failed for $GATE_TARGET"; exit 1; }
