#!/usr/bin/env bash

set -euo pipefail

# example curl:
#curl http://webhook.media.svc.cluster.local/hooks/qbit-pushover --header 'Content-Type: application/json' --data-raw '{"name": "%N", "cat": "%L", "size": "%Z", "indexer": "%T"}'

# Function to send pushover notification
notify() {
	printf -v PUSHOVER_TITLE "%s" "Download Finished"
	printf -v PUSHOVER_MESSAGE \
		"<b>%s</b><small>\n<b>Category:</b> %s</small><small>\n<b>Indexer:</b> %s</small><small>\n<b>Size:</b> %s</small>" \
			"${RELEASE_NAME%.*}" \
			"${RELEASE_CAT}" \
			"${RELEASE_INDEXER}" \
			"$(numfmt --to iec --format "%8.2f" "${RELEASE_SIZE}")"
	printf -v PUSHOVER_PRIORITY "%s" "low"

	apprise -vv --title "${PUSHOVER_TITLE}" -i html --body "${PUSHOVER_MESSAGE}" \
		"${QBIT_PUSHOVER_URL}?priority=${PUSHOVER_PRIORITY}&format=html"
}

main() {
	notify
}

main "$@"
