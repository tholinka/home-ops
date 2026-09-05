set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

controller := `just talos get-controller`
nodes := `just talos get-nodes`

[confirm('Bootstrap cluster? [y|N]')]
[doc('Bootstrap Kubernetes')]
cluster: (kubeconfig "node") wait-for-nodes crds resources apps kubeconfig

[doc('Bootstrap Talos')]
talos:
    just log info "Running stage..." "stage" "$(basename $0)"

    just talos topf apply --auto-bootstrap

    just talos topf kubeconfig > ~/.kube/config
    if [ $? -ne 0 ]; then
        just log fatal "Failed to fetch kubeconfig" "stage" "$(basename $0)"
        exit 1
    fi

    just talos topf talosconfig > ~/.talos/config
    if [ $? -ne 0 ]; then
        just log fatal "Failed to fetch talosconfig" "stage" "$(basename $0)"
        exit 2
    fi

[doc('Fetch kubeconfig')]
kubeconfig lb="cilium":
    just log info "Running stage..." "stage" "$(basename $0)"

    # use the controller as endpoint during bootstrap,
    # and then after, it should already be the dns name, but sometimes its the ip, so force it to use the dns name
    if [[ "{{ lb }}" != "cilium" ]]; then
        if ! kubectl config set-cluster kubernetes --server "https://{{ controller }}:6443"; then
            just log fatal "Failed to set kubectl cluster server address" "stage" "$(basename $0)"
        fi
    else
        kubectl config set-cluster kubernetes --server "https://cluster.servers.internal:6443"
    fi

[private]
wait-for-nodes:
    just log info "Running stage..." "stage" "$(basename $0)"
    if ! kubectl wait nodes --for=condition=Ready=True --all --timeout=1s &>/dev/null; then
        until kubectl wait nodes --for=condition=Ready=False --all --timeout=5s &>/dev/null; do
            just log info "Nodes not available, waiting for nodes to be available. Retrying in 5 seconds..." "stage" "$(basename $0)"
            sleep 5
        done
    fi

[private]
crds:
    just log info "Running stage..." "stage" "$(basename $0)"

    if ! helmfile -f "{{ source_directory() }}/helmfile.d/00-crds.yaml" template -q | yq ea -e 'select(.kind == "CustomResourceDefinition")' | kubectl apply --server-side --force-conflicts -f -; then
        just log fatal "Failed to apply crds" "stage" "$(basename $0)"
    fi

[private]
resources:
    just log info "Running stage..." "stage" "$(basename $0)"
    if ! just template "{{ source_directory() }}/resources.yaml.j2" | kubectl apply --server-side --force-conflicts -f -; then
        just log fatal "Failed to apply resources" "stage" "$(basename $0)"
    fi

[private]
apps:
    just log info "Running stage..." "stage" "$(basename $0)"
    if ! helmfile -f "{{ source_directory() }}/helmfile.d/01-apps.yaml" sync --hide-notes; then
        just log fatal "Failed to sync helmfile" "stage" "$(basename $0)"
    fi

# rook's auto wipe cant handle encrypted drives :(
[confirm('Wipe rook disks? [y|N]')]
[doc('Wipe rook disks')]
wipe-rook-disks:
    ROOK_DISK_0='SPCC M.2 PCIe SSD'
    ROOK_DISK_1='SPCC M.2 SSD'

    just log info "Running stage..." "stage" "$(basename $0)"

    # Skip disk wipe if Rook is detected running in the cluster
    # TODO: Is there a better way to detect Rook / OSDs?
    if kubectl --namespace rook-ceph get kustomization rook-ceph &>/dev/null; then
        just log warn "Rook is detected running in the cluster, skipping disk wipe" "stage" "$(basename $0)"
        exit 1
    fi

    # Wipe disks on each node that match the ROOK_DISK environment variable
    for node in {{ nodes }}; do
        # see kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml -> spec.values.cephClusterSpec.storage.devicePathFilter, that regex needs to match these models!
        disks=$(talosctl --nodes "${node}" get disk --output yaml 2>/dev/null \
          | yq eval-all "[.] | map(select(.spec.model == \"${ROOK_DISK_0}\" or .spec.model == \"${ROOK_DISK_1}\") | .metadata.id) | join(\" \")")

        if [[ -z $disks ]]; then
            just log debug "Talos node has no disk matching models" node "${node}" model "${ROOK_DISK_0} or ${ROOK_DISK_1}" "stage" "$(basename $0)"
            continue
        fi

        just log debug "Talos node and disk discovered" node "${node}" disks "${disks}" "stage" "$(basename $0)"

        # Remove any dmsetup devices that may be present on the node
        just log debug "Wiping encrypted ceph dmsetup devices on node" node "${node}" "stage" "$(basename $0)"
        talosctl debug ubuntu -n ${node} --args /bin/bash --args '-c' \
                  --args 'export DEBIAN_FRONTEND=noninteractive ; apt-get update -y 1>/dev/null && apt-get install dmsetup -y 1>/dev/null && dmsetup ls | grep ceph | while read name rest; do dmsetup remove $name && echo dmsetup removed $name; done'

        # Wipe each disk on the node
        for disk in ${disks}; do
            if talosctl --nodes "${node}" wipe disk "${disk}"; then
                just log info "Disk wiped" node "${node}" disk "${disk}" "stage" "$(basename $0)"
            else
                just log fatal "Failed to wipe disk node " node "${node}" disk "${disk}" "stage" "$(basename $0)"
            fi
        done
    done
