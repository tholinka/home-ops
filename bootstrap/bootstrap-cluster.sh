#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

export LOG_LEVEL="debug"
ROOT_DIR="$(git rev-parse --show-toplevel)"
export ROOT_DIR

# Apply the Talos configuration to all the nodes
function apply_talos_config() {
	log debug "Applying Talos configuration"

	task talos:generate-config

	cp talos/clusterconfig/talosconfig "$HOME/.talos/config"

	# Apply the Talos configuration to the nodes
	if ! nodes=$(talosctl config info --output json 2>/dev/null | jq --exit-status --raw-output '.nodes | join(" ")') || [[ -z "${nodes}" ]]; then
		log error "No Talos nodes found"
	fi

	log debug "Talos nodes discovered" "nodes=${nodes}"

	pushd "${ROOT_DIR}/talos" >/dev/null

	# Apply the Talos configuration
	for node in ${nodes}; do
		log debug "Applying Talos node configuration" "node=${node}"

		if ! output=$(talhelper gencommand apply --node "${node}" --extra-flags="--insecure" | bash 2>&1);
		then
			if [[ "${output}" == *"certificate required"* ]]; then
				log warn "Talos node is already configured, skipping apply of config" "node=${node}"
				continue
			fi
			log error "Failed to apply Talos node configuration" "node=${node}" "output=${output}"
		fi

		log info "Talos node configuration applied successfully" "node=${node}"
	done

	popd
}

# Bootstrap Talos on a controller node
function bootstrap_talos() {
	log debug "Bootstrapping Talos"

	pushd "${ROOT_DIR}/talos" >/dev/null

	if ! controller=$(talosctl config info --output json | jq --exit-status --raw-output '.endpoints[]' | shuf -n 1) || [[ -z "${controller}" ]]; then
		log error "No Talos controller found"
	fi

	log debug "Talos controller discovered" "controller=${controller}"

	until output=$(talosctl --talosconfig=./clusterconfig/talosconfig --nodes="${controller}" bootstrap 2>&1 || true) && [[ "${output}" == *"AlreadyExists"* ]]; do
		log info "Talos bootstrap in progress, waiting 10 seconds..." "controller=${controller}"
		sleep 10
	done

	popd >/dev/null
}

# Fetch the kubeconfig from a controller node
function fetch_kubeconfig() {
	log debug "Fetching kubeconfig"

	pushd "${ROOT_DIR}/talos" >/dev/null

	if ! controller=$(talosctl config info --output json | jq --exit-status --raw-output '.endpoints[]' | shuf -n 1) || [[ -z "${controller}" ]]; then
		log error "No Talos controller found"
	fi

	if ! talosctl kubeconfig --nodes "${controller}" --force --force-context-name main "$(basename "${ROOT_DIR}/kubeconfig")" &>/dev/null; then
		log error "Failed to fetch kubeconfig"
	fi

	if [[ $1 = 'bootstrap' ]]; then
		# use the controller as the endpoint for now
		if sed --version &> /dev/null; then # macos sed is annoying
			sed -i "s/cluster.servers.internal/${controller}/g" "${ROOT_DIR}/kubeconfig"
		else
			sed -i '' "s/cluster.servers.internal/${controller}/g" "${ROOT_DIR}/kubeconfig"
		fi
	else
		# should already be the dns name, but sometimes its the ip, so force it to use the dns name
		if sed --version &> /dev/null; then # macos sed is annoying
			sed -i "s/192\.168\.20\.../cluster.servers.internal/g" "${ROOT_DIR}/kubeconfig"
		else
			sed -i '' "s/192\.168\.20\.../cluster.servers.internal/g" "${ROOT_DIR}/kubeconfig"
		fi
	fi

	cp "${ROOT_DIR}/kubeconfig" "$HOME/.kube/config"

	log info "Kubeconfig fetched successfully"

	popd >/dev/null
}

# Talos requires the nodes to be 'Ready=False' before applying resources
function wait_for_nodes() {
	log debug "Waiting for nodes to be available"

	# Skip waiting if all nodes are 'Ready=True'
	if kubectl wait nodes --for=condition=Ready=True --all --timeout=1s &>/dev/null; then
		log info "Nodes are available and ready, skipping wait for nodes"
		return
	fi

	# Wait for all nodes to be 'Ready=False'
	until kubectl wait nodes --for=condition=Ready=False --all --timeout=10s &>/dev/null; do
		log info "Nodes are not available, waiting for nodes to be available. Retrying in 10 seconds..."
		sleep 10
	done
}

# CRDs to be applied before the helmfile charts are installed
function apply_crds() {
	log debug "Applying CRDs"

	local -r helmfile_file="${ROOT_DIR}/bootstrap/helmfile.d/00-crds.yaml"

	if [[ ! -f "${helmfile_file}" ]]; then
		log error "File does not exist" "file=${helmfile_file}"
	fi

	if ! helmfile --file "${helmfile_file}" template -q | yq ea -e 'select(.kind == "CustomResourceDefinition")' | kubectl apply --server-side --field-manager bootstrap --force-conflicts -f -; then
		log error "Failed to apply CRDs"
	fi

	log info "CRDs synced successfully"
}

# Resources to be applied before the helmfile charts are installed
function apply_resources() {
	log debug "Applying resources"

	local -r resources_file="${ROOT_DIR}/bootstrap/resources.yaml.j2"

	if ! output=$(render_template "${resources_file}") || [[ -z "${output}" ]]; then
		exit 1
	fi

	if echo "${output}" | kubectl diff --filename - &>/dev/null; then
		log info "Resources are up-to-date"
		return
	fi

	if response=$(echo "${output}" | kubectl apply --server-side --filename - 2>&1); then
		log info "Resources applied"
	else
		log error "Failed to apply resources" "response=${response}"
	fi
}

# Sync Helm releases
function sync_helm_releases() {
	log debug "Syncing Helm releases"

	local -r helmfile_file="${ROOT_DIR}/bootstrap/helmfile.d/01-apps.yaml"

	if [[ ! -f "${helmfile_file}" ]]; then
		log error "File does not exist" "file=${helmfile_file}"
	fi

	if ! helmfile --file "${helmfile_file}" sync --hide-notes; then
		log error "Failed to sync Helm releases"
	fi

	log info "Helm releases synced successfully"
}

function main() {
	check_env KUBECONFIG
	check_cli helmfile jq kubectl kustomize minijinja-cli bws talosctl yq sed

	if ! bws project list &>/dev/null; then
		log error "Failed to authenticate with Bitwarden Seccret Manager CLI"
	fi

	# # Bootstrap the Talos node configuration
	apply_talos_config
	bootstrap_talos
	fetch_kubeconfig bootstrap

	# Apply resources and Helm releases
	wait_for_nodes
	apply_crds
	apply_resources
	sync_helm_releases

	fetch_kubeconfig done

	log info "Congrats! The cluster is bootstrapped and Flux is syncing the Git repository"
}

main "$@"
