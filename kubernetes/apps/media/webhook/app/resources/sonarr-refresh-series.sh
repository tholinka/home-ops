#!/usr/bin/env bash
set -Eeuo pipefail

SONARR_URL=${1:?}
SONARR_API_KEY=${2:?}
PAYLOAD=${3:?}

echo "[DEBUG] Payload: ${PAYLOAD}"

function _jq() {
	jq --raw-output "${1:?}" <<< "${PAYLOAD}"
}

function refresh() {
	local event="$(_jq '.eventType')"
	local series_id="$(_jq '.series.id')"
	local series_title="$(_jq '.series.title')"

	if [[ "${event}" == "Test" ]]; then
		echo "Test event received, nothing to do ..."
	fi

	if [[ "${event}" == "Grab" ]]; then
		episodes=$(\
			curl -fsSL --header "X-Api-Key: ${SONARR_API_KEY}" "${SONARR_URL}/api/v3/episode?seriesId=${series_id}" \
				| jq --raw-output '[.[] | select((.title == "TBA") or (.title == "TBD"))] | length' \
		)

		if (( episodes > 0 )); then
			echo "TBA/TBD episode titles found, refreshing series ${series_title} ..."
			curl -fsSL --request POST \
				--header "X-Api-Key: ${SONARR_API_KEY}" \
				--header "Content-Type: application/json" \
				--data-binary "$(jo name=RefreshSeries seriesId="${series_id}")" \
				"${SONARR_URL}/api/v3/command"
		fi
	fi
}

function main() {
	refresh
}

main "$@"
