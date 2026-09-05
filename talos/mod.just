set default-list
set default-script
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

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

[confirm('Apply Talos config for cluster? [y|N] ?')]
[doc('Apply Talos config to the entire cluster')]
apply-cluster:
    topf apply
    just talos healthy-nodes

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

reset-cluster:
    topf reset --full=false --wait-for-maintenance

[doc('Wrapper around topf to run in the talos folder')]
topf *args:
    topf {{ args }}
