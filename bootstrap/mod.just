set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

controller := `just talos get-controller`
nodes := `just talos get-nodes`

[confirm('Bootstrap cluster? [y|N]')]
[doc('Bootstrap Talos and Kubernetes')]
cluster: talos kube (kubeconfig "node") wait-for-nodes crds resources apps kubeconfig

[private]
talos:
    just log info "Running stage..." "stage" "$(basename $0)"

    just talos generate-config
    just talos copy-config

    for n in {{ nodes }}; do
        if ! op=$(just --yes talos apply-node "$n" --insecure 2>&1); then
            if [[ "$op" == *"certificate required"* ]]; then
                just log info "Talos already configured, skipping apply of config" "stage" "$(basename $0)" "node" "$n"
                continue
            fi
            just log fatal "Failed to apply Talos configuration" "stage" "$(basename $0)" "node" "$n" "output" "$op"
        fi
    done

[private]
kube:
    just log info "Running stage..." "stage" "$(basename $0)"
    until op=$(talosctl -n "{{ controller }}" bootstrap 2>&1 || true) && [[ "$op" == *"AlreadyExists"* ]]; do
        just log info "Kubernetes bootstrap in progress. Retrying in 5 seconds..." "stage" "$(basename $0)"
        sleep 5
    done

[doc('Fetch kubeconfig')]
kubeconfig lb="cilium":
    just log info "Running stage..." "stage" "$(basename $0)"
    if ! talosctl kubeconfig -n "{{ controller }}" -f --force-context-name main {{ justfile_dir() }}; then
        just log fatal "Failed to fetch kubeconfig" "stage" "$(basename $0)"
    fi
    # use the controller as endpoint during bootstrap,
    # and then after, it should already be the dns name, but sometimes its the ip, so force it to use the dns name
    if [[ "{{ lb }}" != "cilium" ]]; then
        if ! kubectl config set-cluster main --server "https://{{ controller }}:6443"; then
            just log fatal "Failed to set kubectl cluster server address" "stage" "$(basename $0)"
        fi
    else
        kubectl config set-cluster main --server "https://cluster.servers.internal:6443"
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
