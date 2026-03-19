#!/usr/bin/env bash
set -Eeuo pipefail

# Environment variables set by the user
QUI_HOST="${QUI_HOST:?}"
QUI_API_KEY="${QUI_API_KEY:?}"
QUI_SLEEP_INTERVAL="${QUI_SLEEP_INTERVAL:-30}"

# Environment variables set by sabnzbd
SAB_COMPLETE_DIR="${SAB_COMPLETE_DIR:?}"
SAB_PP_STATUS="${SAB_PP_STATUS:?}"

# Function to search for cross-seed
search() {
    local status_code
    status_code=$(curl \
        --silent \
        --output /dev/null \
        --write-out "%{http_code}" \
        --request POST \
        --data "{\"path\": \"${SAB_COMPLETE_DIR}\"}" \
        --header "accept: application/json" \
		--header "X-API-Key: ${QUI_API_KEY}" \
		--header "Content-Type: application/json" \
        "http://${QUI_HOST}/api/dir-scan/webhook/scan"
    )

    printf "qui search returned with HTTP status code %s and path %s\n" "${status_code}" "${SAB_COMPLETE_DIR}" >&2

    sleep "${QUI_SLEEP_INTERVAL}"
}

main() {
    # Check if post-processing was successful
    if [[ "${SAB_PP_STATUS}" -ne 0 ]]; then
        printf "post-processing failed with sabnzbd status code %s\n" "${SAB_PP_STATUS}" >&2
        exit 1
    fi

    search
}

main "$@"
