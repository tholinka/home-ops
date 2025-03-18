#!/usr/bin/env bash
# from https://github.com/onedr0p/home-ops/blob/main/kubernetes/apps/default/bazarr/app/resources/subcleaner.sh
printf "Cleaning subtitles for '%s' ...\n" "$1"
python3 /subcleaner/subcleaner/subcleaner.py "$1" -s

case $1 in
    *movies*) section="1";;
    *shows*) section="2";;
esac

if [[ -n "$section" ]]; then
    printf "Refreshing Plex section '%s' for '%s' ...\n" "$section" "$(dirname "$1")"
    /usr/bin/curl -I -X GET -G \
        --data-urlencode "path=$(dirname "$1")" \
        --data-urlencode "X-Plex-Token=${PLEX_TOKEN}" \
        --no-progress-meter \
            "http://plex.media.svc.cluster.local:32400/library/sections/${section}/refresh"
fi
