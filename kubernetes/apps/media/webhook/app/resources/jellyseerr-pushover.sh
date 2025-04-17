#!/usr/bin/env bash
set -Eeuo pipefail

function notify() {
	if [[ "${EVENT_TYPE}" == "TEST_NOTIFICATION" ]]; then
		printf -v PUSHOVER_TITLE "%s: %s" "$EVENT_EVENT" "$EVENT_SUBJECT"
		printf -v PUSHOVER_MESSAGE "Howdy this is a test notification\n%S" "$EVENT_MESSAGE"
		printf -v PUSHOVER_PRIORITY "low"
	elif [[ ${EVENT_TYPE} == "MEDIA_AVAILABLE" ]]; then
		printf -v PUSHOVER_TITLE "%s: %s" "$EVENT_EVENT" "$EVENT_SUBJECT"
		printf -v PUSHOVER_MESSAGE "<small><b>Requested By:</b> %s</small><small>\t<b>Status:</b> %s</small><small>\t<b>Type:</b> %s</small><small>\n%s</small>" \
		"$EVENT_REQUESTED_BY" \
		"$EVENT_MEDIA_STATUS" \
		"$EVENT_MEDIA_TYPE" \
		"$EVENT_MESSAGE"
		printf -v PUSHOVER_PRIORITY "low"
	else
		printf -v "PUSHOVER_TITLE" "Unknown Event Type: %s" "$EVENT_TYPE"
		printf -v "PUSHOVER_MESSAGE" "%s: %s\n%s" "$EVENT_EVENT" "$EVENT_SUBJECT" "$EVENT_MESSAGE"
		printf -v PUSHOVER_PRIORITY "emergency"
	fi

	printf -v PUSHOVER_URL "https://requests.%s" "${SECRET_DOMAIN}"
	printf -v PUSHOVER_URL_TITLE "Open Request"

	apprise -vv --title "${PUSHOVER_TITLE}" --body "${PUSHOVER_MESSAGE}" --input-format html \
		"${JELLYSEERR_PUSHOVER_URL}?url=${PUSHOVER_URL}&url_title=${PUSHOVER_URL_TITLE}&priority=${PUSHOVER_PRIORITY}&format=html"
}

function main() {
	notify
}

main "$@"
