#!/usr/bin/env bash
set -Eeuo pipefail

PUSHOVER_URL=${1:?}

function notify() {
	if [[ "${EVENT_TYPE}" == "TEST" ]]; then
		printf -v pushover_title "Test Notification"
		printf -v pushover_msg "Howdy this is a test notification from <b>%s</b>" "cross-seed"
		printf -v pushover_priority "%s" "low"
	fi

	if [[ "${EVENT_TYPE}" == "RESULTS" && "${EVENT_RESULT}" == "INJECTED" ]]; then
		printf -v pushover_title "Cross-Seed Injection"
		printf -v pushover_msg "<b>%s</b><small>\n<b>Category:</b> %s</small><small>\n<b>Partial Match (Paused):</b> %s</small><small>\n<b>Source:</b> %s</small><small>\nFrom %s to %s</small>" \
			"${EVENT_NAME}" \
			"${EVENT_CATEGORY}" \
			"${EVENT_PAUSED}" \
			"${EVENT_TO_TRACKER}" \
			"${EVENT_FROM_TRACKER}" \
			"${EVENT_SOURCE}"

		printf -v pushover_url "https://qb.${SECRET_DOMAIN}/#/torrent/%s" "${EVENT_HASH}"
		printf -v pushover_url_title "View in qbit"

		printf -v pushover_priority "%s" \
			"$([[ ${EVENT_PAUSED} == 'true' ]] && echo "emergency" || echo "low")"
	fi

	apprise -vv --title "${pushover_title}" -i html --body "${pushover_msg}" \
		"${PUSHOVER_URL}?url=${pushover_url}&url_title=${pushover_url_title}&priority=${pushover_priority}&format=html"
}

function main() {
	notify
}

main "$@"
