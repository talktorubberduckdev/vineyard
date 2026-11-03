#!/usr/bin/env bash
# Renders every chart in charts/ for each environment into <deploy-repo>/apps/<chart>/<env>/<chart>.yaml.
# An environment is skipped when the chart has no values-<env>.yaml.
set -euo pipefail

out="${1:?usage: render.sh <deploy-repo-dir>}"
namespace="${NAMESPACE:-vineyard}"
environments="${ENVIRONMENTS:-dev test prod}"
root="$(cd "$(dirname "$0")/.." && pwd)"

for chart_yaml in "$root"/charts/*/Chart.yaml; do
  chart_dir="$(dirname "$chart_yaml")"
  chart="$(basename "$chart_dir")"

  if grep -q '^dependencies:' "$chart_yaml"; then
    # helm dependency build only knows repositories registered on this machine; CI starts with none.
    for url in $(awk '$1 == "repository:" {print $2}' "$chart_yaml" | sort -u); do
      helm repo add --force-update "dep-$(printf '%s' "$url" | sha1sum | cut -c1-8)" "$url"
    done
    helm dependency build "$chart_dir"
  fi

  for env in $environments; do
    values="$chart_dir/values-$env.yaml"
    if [ ! -f "$values" ]; then
      echo "skip $chart/$env: no values-$env.yaml"
      continue
    fi

    target="$out/apps/$chart/$env"
    mkdir -p "$target"
    # Drop previous output so templates removed from the chart disappear from the deploy repo.
    find "$target" -maxdepth 1 -name '*.yaml' -delete
    helm template "$chart" "$chart_dir" --namespace "$namespace" --include-crds -f "$values" > "$target/$chart.yaml"
    echo "rendered $chart/$env"
  done
done
