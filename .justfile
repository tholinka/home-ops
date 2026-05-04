#!/usr/bin/env -S just --justfile

set lazy
set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']

mod bootstrap "bootstrap"
mod kube "kubernetes"
mod talos "talos"

[private]
default:
    just -l

[private]
log lvl msg *args:
    gum log -t rfc3339 -s -l "{{ lvl }}" "{{ msg }}" {{ args }}

[private]
template file *args:
    bws run --no-inherit-env -- minijinja-cli --env "{{ file }}" {{ args }}

[doc('Setup Brew')]
setup-brew:
    brew bundle --file /dev/stdin <<< EOF \
    tap "siderolabs/tap" \
    brew "siderolabs/tap/talosctl"\
    brew "helm" \
    brew "jq" \
    brew "yq" \
    brew "k9s" \
    brew "krew" \
    brew "kubecolor" \
    brew "kubeconform" \
    brew "kubernetes-cli" \
    brew "kustomize" \
    brew "mise" \
    brew "viddy" \
    EOF

[doc('Setup krew')]
setup-krew:
    kubectl krew update
    kubectl krew upgrade
    kubectl krew install cert-manager browse-pvc node-shell rook-ceph view-secret
