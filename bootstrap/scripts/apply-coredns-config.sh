#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

export LOG_LEVEL="debug"
export ROOT_DIR="$(git rev-parse --show-toplevel)"

function apply_config() {
    check_cli kubectl kustomize

    log debug "Applying Coredns config"

    local -r config_dir="${ROOT_DIR}/kubernetes/apps/kube-system/coredns/config"

    if [[ ! -d "${config_dir}" ]]; then
        log error "No Coredns config directory found" "directory=${config_dir}"
    fi

    if kubectl --namespace kube-system diff --kustomize "${config_dir}" &>/dev/null; then
        log info "Coredns config is up-to-date"
    else
        if kubectl apply --namespace kube-system --server-side --field-manager kustomize-controller --kustomize "${config_dir}" &>/dev/null; then
            log info "Coredns config applied successfully"
        else
            log error "Failed to apply Coredns config"
        fi
    fi
}

function main() {
    apply_config
}

main "$@"
