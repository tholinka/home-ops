#!/usr/bin/env bash
# shellcheck disable=SC2154
# from https://github.com/onedr0p/home-ops/blob/main/kubernetes/apps/default/sonarr/app/resources/tba-refresher.sh
set -euo pipefail

CURL_CMD=(curl -fsSL --header "X-Api-Key: ${SONARR__AUTH__APIKEY:-}")
SONARR_API_URL="http://localhost:${SONARR__SERVER__PORT:-}/api/v3"

if [[ "${sonarr_eventtype:-}" == "Grab" ]]; then
    tba=$("${CURL_CMD[@]}" "${SONARR_API_URL}/episode?seriesId=${sonarr_series_id:-}" | jq --raw-output '
        [.[] | select((.title == "TBA") or (.title == "TBD"))] | length
    ')

    if (( tba > 0 )); then
        echo "INFO: Refreshing series ${sonarr_series_id:-} due to TBA/TBD episodes found"
        "${CURL_CMD[@]}" \
            --request POST \
            --header "Content-Type: application/json" \
            --data-binary '{"name": "RefreshSeries", "seriesId": '"${sonarr_series_id:-}"'}' \
            "${SONARR_API_URL}/command" &>/dev/null
    fi
fi
