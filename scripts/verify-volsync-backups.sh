#!/usr/bin/env bash
# dry-run restore of all volsync backups to ensure there's no corruption

set -Eeou pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

RESTIC_PASSWORD=${RESTIC_PASSWORD:=}

if [[ -z "$RESTIC_PASSWORD" ]]; then
    read -sp 'Restic password: ' RESTIC_PASSWORD
fi

export RESTIC_PASSWORD

set -x;

for i in "/raid/backups/Volsync/"*; do
    echo "verifying backup of $i"
    restic restore --target "/tmp/restore-${i##*/}" --dry-run --verbose=1 latest -r "$i"
done
