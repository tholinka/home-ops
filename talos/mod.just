set lazy
set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']

nodes := `just talos get-nodes`

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
    controller="$(just talos get-controller)"; \
    until talosctl --nodes $controller health; \
        do sleep 5; \
        controller="$(just talos get-controller)"; \
    done

[doc('Generate Talos config for all nodes')]
generate-config:
    bws run --no-inherit-env -- talhelper genconfig

[doc('Apply Talos config to a node')]
apply-node node mode="auto":
    talhelper gencommand apply --node {{ node }} --extra-flags '--mode={{ mode }}' | bash
    just talos healthy-nodes

[doc('Apply Talos config to the entire cluster')]
apply-cluster mode="auto":
    for node in {{ nodes }}; do \
        just talos apply-node "$node" "{{ mode }}"; \
        echo;\
    done

[doc('Download Talos machine image')]
download-image version schematic:
    gum spin --title "Downloading Talos {{ version }} ..." -- \
    curl -sfL --remove-on-error --retry 5 --retry-delay 5 --retry-all-errors \
        -o "talos-{{ version }}-{{ replace_regex(schematic, '^(.{8}).*', '$1') }}.iso" \
        "https://factory.talos.dev/image/{{ schematic }}/{{ version }}/metal-amd64.iso"
    just log info "Downloaded Talos" version "{{ version }}" schematic "{{ schematic }}"

[doc('Reboot a node')]
reboot-node node:
    gum confirm "Reboot node {{ node }}?" --default="No" && \
        echo "did reboot" #talosctl -n {{ node }} reboot -m powercycle || exit 0
    just talos healthy-nodes

[doc('Reboot entire cluster')]
reboot-cluster:
    for node in {{ nodes }}; do \
        just talos reboot-node "$node"; \
    done

[private]
do-shutdown-node node *args:
    talosctl -n "{{ node }}" shutdown --force {{ args }} || exit 0

[doc('Shutdown a node')]
shutdown-node node *args:
    gum confirm "Shutdown node {{ node }}?" --default="No" && \
        just talos do-shutdown-node {{ node }} {{ args }} || exit 0

[doc('Shutdown entire cluster')]
shutdown-cluster *args:
    if gum confirm "Shutdown cluster?" --default="No"; then \
        for node in {{ nodes }}; do \
            just talos do-shutdown-node $node {{ args }} || exit 0; \
        done \
    fi

[private]
do-reset-node node CLI_FORCE="":
    if [[ "{{ CLI_FORCE }}" != "true" ]]; then \
        flags="--system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL"; \
    fi; \
    talhelper gencommand reset --extra-flags="--reboot $flags --graceful=false --wait=false" | bash

[doc('Reset a node')]
reset-node node CLI_FORCE="":
    gum confirm "Reset node {{ node }}?" --default="No" && \
        just talos do-reset-node {{ node }} {{ CLI_FORCE }}

[doc('Reset entire cluster')]
reset-cluster CLI_FORCE="":
    if gum confirm "Reset cluster?" --default="No"; then \
        for node in {{ nodes }}; do \
            just talos do-reset-node "$node" {{ CLI_FORCE }}; \
        done \
    fi
