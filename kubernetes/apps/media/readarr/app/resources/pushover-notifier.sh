#!/usr/bin/env bash
# shellcheck disable=SC2154
# from https://github.com/onedr0p/home-ops/blob/main/kubernetes/apps/default/readarr/app/resources/pushover-notifier.sh
set -euo pipefail

# User defined variables for pushover
PUSHOVER_USER_KEY="${PUSHOVER_USER_KEY:-required}"
PUSHOVER_TOKEN="${PUSHOVER_TOKEN:-required}"
PUSHOVER_PRIORITY="${PUSHOVER_PRIORITY:-"-2"}"

if [[ "${readarr_eventtype:-}" == "Test" ]]; then
    PUSHOVER_PRIORITY="1"
    printf -v PUSHOVER_TITLE \
        "Test Notification"
    printf -v PUSHOVER_MESSAGE \
        "Howdy this is a test notification from %s" \
            "${readarr_instancename:-readarr}"
    printf -v PUSHOVER_URL \
        "%s" \
            "${readarr_applicationurl:-localhost}"
    printf -v PUSHOVER_URL_TITLE \
        "Open %s" \
            "${readarr_instancename:-readarr}"
fi

if [[ "${readarr_eventtype:-}" == "Download" ]]; then
    printf -v PUSHOVER_TITLE \
        "Movie %s" \
            "$( [[ "${readarr_isupgrade}" == "True" ]] && echo "Upgraded" || echo "Imported" )"
    printf -v PUSHOVER_MESSAGE \
        "<b>%s (%s)</b><small>\n%s</small><small>\n\n<b>Quality:</b> %s</small><small>\n<b>Size:</b> %s</small><small>\n<b>Client:</b> %s</small><small>\n<b>Indexer:</b> %s</small>" \
            "${readarr_movie_title}" \
            "${readarr_movie_year}" \
            "${readarr_movie_overview}" \
            "${readarr_moviefile_quality:-Unknown}" \
            "$(numfmt --to iec --format "%8.2f" "${readarr_release_size:-0}")" \
            "${readarr_download_client:-Unknown}" \
            "${readarr_release_indexer:-Unknown}"
    printf -v PUSHOVER_URL \
        "%s/movie/%s" \
            "${readarr_applicationurl:-localhost}" "${readarr_movie_tmdbid}"
    printf -v PUSHOVER_URL_TITLE \
        "View movie in %s" \
            "${readarr_instancename:-readarr}"
fi

if [[ "${readarr_eventtype:-}" == "ManualInteractionRequired" ]]; then
    PUSHOVER_PRIORITY="1"
    printf -v PUSHOVER_TITLE \
        "Movie import requires intervention"
    printf -v PUSHOVER_MESSAGE \
        "<b>%s (%s)</b><small>\n<b>Client:</b> %s</small>" \
            "${readarr_movie_title}" \
            "${readarr_movie_year}" \
            "${readarr_download_client:-Unknown}"
    printf -v PUSHOVER_URL \
        "%s/activity/queue" \
            "${readarr_applicationurl:-localhost}"
    printf -v PUSHOVER_URL_TITLE \
        "View queue in %s" \
            "${readarr_instancename:-readarr}"
fi

json_data=$(jo \
    token="${PUSHOVER_TOKEN}" \
    user="${PUSHOVER_USER_KEY}" \
    title="${PUSHOVER_TITLE}" \
    message="${PUSHOVER_MESSAGE}" \
    url="${PUSHOVER_URL}" \
    url_title="${PUSHOVER_URL_TITLE}" \
    priority="${PUSHOVER_PRIORITY}" \
    html="1"
)

status_code=$(curl \
    --silent \
    --write-out "%{http_code}" \
    --output /dev/null \
    --request POST  \
    --header "Content-Type: application/json" \
    --data-binary "${json_data}" \
    "https://api.pushover.net/1/messages.json" \
)

printf "pushover notification returned with HTTP status code %s and payload: %s\n" \
    "${status_code}" \
    "$(echo "${json_data}" | jq --compact-output)" >&2
