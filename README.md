# Lucida release gate (GitHub Action)

Stops a workflow when a guarded rollout or an experiment is unhealthy. It runs the same checks as
`lucida rollout check` / `lucida experiments check` straight against your Lucida API with `curl` and `jq`
(preinstalled on GitHub-hosted runners; self-hosted runners need both), so no image or CLI install is needed.

| Check | Fails on |
|---|---|
| `rollout` | the rollout was rolled back or aborted, a guardrail breach is recorded, a notify-only breach is unacknowledged, or (without `allow-missing`) the flag has no guarded rollout |
| `experiments` | results unavailable, sample ratio mismatch, guardrail breach, unhealthy multiple exposure, pre-exposure bias, failed A/A test |

From GitHub, [lucidaanalytics/lucida-release-gate](https://github.com/lucidaanalytics/lucida-release-gate), release `v0.1.0`; `uses: lucidaanalytics/lucida-release-gate@v0.1.0` works as soon as the tag exists, and `@v0` follows the newest 0.x release.

```yaml
- uses: lucidaanalytics/lucida-release-gate@v0.1.0
  id: gate
  with:
    check: rollout            # or: experiments
    target: new-checkout      # flag key / experiment name or id
    api-url: https://lucida.example.com
    project: ${{ vars.LUCIDA_PROJECT_ID }}
    api-key: ${{ secrets.LUCIDA_API_KEY }}
- run: jq .checks <<< "$REPORT"
  if: always()
  env:
    REPORT: ${{ steps.gate.outputs.report }}
```

Outputs: `passed` (`true` / `false`) and `report` (the JSON report). The same gate runs anywhere
with the CLI: `lucida rollout check new-checkout --format json`. Pin `@v0.1.0` or a commit sha for a fixed version.

---

This repository is a read-only mirror of the Lucida monorepo (synced by a script, never edited by hand); releases and provenance attestations are built here by GitHub Actions. Issues are welcome, changes land upstream.
