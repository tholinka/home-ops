set default-script
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

# Default ipv6_prefix, overridden by bws when generating config
export ipv6_prefix := "fd00"

[private]
default:
    just -l talos

[doc('Get a controller node ip')]
get-controller:
    talosctl config info --output json | jq --exit-status --raw-output '.endpoints[]' | shuf -n 1

[doc('Get all node ips')]
get-nodes:
    talosctl config info --output json 2>/dev/null | jq --exit-status --raw-output '.nodes | join(" ")'

[doc('Wait for all nodes to be healthy')]
healthy-nodes:
    # shuffle a random ip, that way if the node being upgraded is the one picked we eventually pick one that's up
    controller="$(just talos get-controller)"
    until talosctl --nodes $controller health
        do sleep 5
        controller="$(just talos get-controller)"
    done

[doc('Generate Talos config for all nodes')]
generate-config:
    bws run --no-inherit-env -- talhelper genconfig

[confirm('Apply Talos config to ' + node + ' [y|N] ?')]
[doc('Apply Talos config to a node')]
apply-node node mode="auto":
    talhelper gencommand apply --node {{ node }} --extra-flags '--mode={{ mode }}' | bash
    just talos healthy-nodes

[doc('Apply Talos config to the entire cluster')]
apply-cluster mode="auto":
    for node in $(just talos get-nodes); do
        just --yes talos apply-node "$node" "{{ mode }}"
        echo
    done

[confirm('Upgrade Talos config to ' + node + ' [y|N] ?')]
[doc('Upgrade Talos config to a node')]
upgrade-node node mode="auto":
    talhelper gencommand upgrade --node {{ node }} --extra-flags '--mode={{ mode }}' | bash
    just talos healthy-nodes

[doc('Upgrade Talos config to the entire cluster')]
upgrade-cluster mode="auto":
    for node in $(just talos get-nodes); do
        just --yes talos upgrade-node "$node" "{{ mode }}"
        echo
    done

[doc('Download Talos machine image')]
download-image version schematic:
    curl -fL --remove-on-error --retry 5 --retry-delay 5 --retry-all-errors --progress-bar \
        -o "talos-{{ version }}-{{ replace_regex(schematic, '^(.{8}).*', '$1') }}.iso" \
        "https://factory.talos.dev/image/{{ schematic }}/{{ version }}/metal-amd64.iso"
    just log info "Downloaded Talos" version "{{ version }}" schematic "{{ schematic }}"

[confirm('Reboot node ' + node + ' [y|N] ?')]
[doc('Reboot a node')]
reboot-node node:
    talosctl -n {{ node }} reboot -m powercycle || exit 0
    just talos healthy-nodes

[confirm('Reboot entire cluster? [y|N] ?')]
[doc('Reboot entire cluster')]
reboot-cluster:
    for node in $(just talos get-nodes); do
        just --yes talos reboot-node "$node"
    done

[confirm('Shutdown node ' + node + ' [y|N] ?')]
[doc('Shutdown a node')]
shutdown-node node *args:
    talosctl -n "$(just talos get-nodes)" shutdown --force {{ args }} || exit 0

[confirm('Shutdown entire cluster? [y|N] ?')]
[doc('Shutdown entire cluster')]
shutdown-cluster *args:
    for node in $(just talos get-nodes); do
        just --yes talos shutdown-node $node {{ args }} || exit 0
    done

[confirm('Reset node ' + node + ' [y|N] ?')]
[doc('Reset a node')]
reset-node node CLI_FORCE="":
    if [[ "{{ CLI_FORCE }}" != "true" ]]; then
        flags="--system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL"
    fi
    talhelper gencommand reset --extra-flags="--reboot $flags --graceful=false --wait=false" | bash

[confirm('Reset entire cluster? [y|N] ?')]
[doc('Reset entire cluster')]
reset-cluster CLI_FORCE="":
    for node in $(just talos get-nodes); do
        just --yes talos reset-node "$node" {{ CLI_FORCE }}
    done
