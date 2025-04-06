#!/usr/bin/env bash
set -Eeuo pipefail

PUSHOVER_URL=${1:?}
PAYLOAD=${2:?}

echo "[DEBUG] Payload: ${PAYLOAD}"

function _jq() {
	jq --raw-output "${1:?}" <<< "${PAYLOAD}"
}

function notify() {
	local event="$(_jq '.extra.event')"
	local result="$(_jq '.extra.result')"

	if [[ "${event}" == "TEST" ]]; then
		printf -v pushover_title "Test Notification"
		printf -v pushover_msg "Howdy this is a test notification from <b>%s</b>" "cross-seed"
		printf -v pushover_priority "%s" "low"
	fi

	if [[ "${event}" == "RESULTS" && "${result}" == "INJECTED" ]]; then
		printf -v pushover_title "Cross-Seed Injection"
		printf -v pushover_msg "<b>%s</b><small>\nCategory: %s</small><p>\nPartial Match (Paused): %s</p><small>\nFrom %s to %s</small>\n\n<b>Source:</b> %s</small>" \
			"$(_jq '.extra.name')" \
			"$(_jq '.extra.category')" \
			"$(_jq '.extra.paused')" \
			"$(_jq '.extra.searchee.trackers[0]')" \
			"$(_jq '.extra.trackers[0]')" \
			"$(_jq '.extra.source')"

		printf -v pushover_url "https://qb.${SECRET_DOMAIN}/#/torrent/%s" "$(_jq '.extra.infoHashes')"
		printf -v pushover_url_title "View in qbit"

		printf -v pushover_priority "%s" \
			"$([[ $(_jq '.extra.paused') == 'true' ]] && echo "emergency" || echo "low")"
	fi

	apprise -vv --title "${pushover_title}" --body "${pushover_msg}" \
		"${PUSHOVER_URL}?url=${pushover_url}&url_title=${pushover_url_title}&priority=${pushover_priority}&format=markdown"
}

function main() {
	notify
}

main "$@"
