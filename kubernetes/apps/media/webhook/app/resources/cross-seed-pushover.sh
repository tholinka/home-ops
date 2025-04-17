#!/usr/bin/env bash
set -Eeuo pipefail

PUSHOVER_URL=${1:?}

function notify() {
	if [[ "${EVENT_TYPE}" == "TEST" ]]; then
		printf -v pushover_title "Test Notification"
		printf -v pushover_msg "Howdy this is a test notification"
		printf -v pushover_priority "low"
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

		printf -v pushover_url "https://qb.%s/#/torrent/%s" "${SECRET_DOMAIN}" "${EVENT_HASH}"
		printf -v pushover_url_title "View in qbit"

		printf -v pushover_priority "%s" \
			"$([[ ${EVENT_PAUSED} == 'true' ]] && echo "emergency" || echo "low")"
	fi

	apprise -vv --title "${pushover_title}" --body "${pushover_msg}" --input-format html \
		"${PUSHOVER_URL}?url=${pushover_url}&url_title=${pushover_url_title}&priority=${pushover_priority}&format=html"
}

function main() {
	notify
}

main "$@"
