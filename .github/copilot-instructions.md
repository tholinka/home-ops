---
description: >
  Guidelines for working with the home-ops Kubernetes project. Use when making changes to Kubernetes manifests, Talos configurations, bootstrap scripts, or Helm deployments. Focus on GitOps practices with Flux, proper Kustomization structure, Talos cluster management, and maintaining DRY principle throughout.
---

# home-ops Copilot Instructions

This project is a GitOps-managed Kubernetes homelab with Talos Linux for cluster orchestration. All infrastructure is declarative and managed through git.

## Project Structure

### Kubernetes Applications (`kubernetes/apps/`)
Organized by category (media, network, database, observability, etc.), each containing multiple applications.

**Three-tier Kustomization hierarchy:**
- **Namespace level** (`kubernetes/kustomization.yaml`): Top-level kubernetes kustomization that declares namespaces and references categories
- **Category level** (`kubernetes/apps/{category}/ks.yaml`): Flux `kustomize.toolkit.fluxcd.io/v1` CRDs; can contain multiple YAML documents (one Flux Kustomization per app)
- **App level** (`kubernetes/apps/{category}/{app}/app/kustomization.yaml`): Kubernetes kustomization that defines the actual K8s resources for the app

**Per-app structure:**
```
app-name/
├── ks.yaml                          # Referenced by category-level ks.yaml (entry point for this app)
└── app/
    ├── kustomization.yaml           # K8s resources (Helm values, PVCs, etc.)
    ├── helmrelease.yaml             # Helm chart specification
    ├── pvc.yaml                     # Persistent volumes (if needed)
    └── resourceclaimtemplate.yaml   # VolSync templates
```

### Talos Configuration (`talos/`)
- **talconfig.yaml**: Single source-of-truth for cluster configuration; uses YAML anchors extensively for DRY
- **talsecret.yaml**: Secrets file (encrypted/excluded)
- **patches/**: Structured patches (global/ for all nodes, controller/ for control plane)
- **clusterconfig/**: Generated per-node configs (kubernetes-{h1-h4,l1-l3}.yaml)

### Bootstrap & Deployment (`bootstrap/`)
- **bootstrap-cluster.sh**: Main entry point with structured logging
- **lib/common.sh**: Shared functions for logging, talosctl commands
- **helmfile.d/**: Helm chart organization for bootstrap only (00-crds.yaml for CRDs, 01-apps.yaml for apps); see Helm section for post-bootstrap deployment

## Naming Conventions

- **Categories**: Lowercase, descriptive (media, network, database, observability, security, home-automation, etc.)
- **Applications**: Lowercase with hyphens (qbittorrent, home-assistant, cloudflare-tunnel, pihole)
- **Namespaces**: Match category names; declared once at category kustomization level
- **Variables/substitutions**: UPPERCASE (APP, VOLSYNC_CAPACITY, NAMESPACE)

## Namespace Descriptions

- **actions-runner-system**: GitHub Actions self-hosted runners for CI/CD workflows
- **database**: Database services (PostgreSQL, Dragonfly, VernemQ)
- **flux-system**: Flux CD deployment and management
- **home-automation**: Home automation services (Home Assistant, ESPHome, Zigbee, Z-Wave)
- **kube-system**: Kubernetes system components (Cilium, CoreDNS, metrics-server)
- **media**: Media services (Plex, Radarr, Sonarr, Lidarr, etc.)
- **network**: Network services (Pihole, Cloudflare Tunnel, dnscrypt-proxy)
- **observability**: Monitoring and logging (Prometheus, Grafana, Victoria Logs)
- **openebs-system**: OpenEBS storage system
- **renovate**: Dependency update automation
- **rook-ceph**: Rook/Ceph distributed storage
- **security**: Security and authentication services
- **self-hosted**: Self-hosted applications (documentation, code servers, etc.)
- **system**: System-level applications and utilities
- **system-controllers**: System control planes
- **system-upgrade**: System upgrade management

When adding new apps, choose the most relevant namespace based on the app's purpose. If uncertain, review similar apps in the project to find the appropriate namespace.

## Coding Patterns

### Kustomization Files (ks.yaml - Category Level)

Category-level `ks.yaml` files contain multiple Flux Kustomization CRD documents (separated by `---`), one per app.

**Per-app Flux Kustomization using YAML anchors for DRY principles:**
```yaml
---
# yaml-language-server: $schema=https://schemas.tholinka.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app homepage
  namespace: &namespace self-hosted
spec:
  interval: 1h
  components:
    - ../../../../components/ext-auth
  path: ./kubernetes/apps/self-hosted/homepage/app
  postBuild:
    substitute:
      APP: *app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: *namespace

```

**Common patterns in app-level ks.yaml:**
- Reference shared components via relative paths
- Declare dependencies explicitly with `dependsOn`
- Use `postBuild.substitute` for environment-specific values
  - Always define `APP` substitution with the app name when using components
- All ks.yaml files reference `sourceRef: flux-system` (implicit)

### App-level Kustomization (kubernetes/apps/{category}/{app}/app/kustomization.yaml)

Define K8s resources and Helm releases for each app:
```yaml
# yaml-language-server: $schema=https://json.schemastore.org/kustomization.json
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrelease.yaml
  - pvc.yaml
```

### Helm Releases

- Store HelmRelease in Flux CRD format in `app/helmrelease.yaml`
- HelmRelease is a Flux custom resource (helm.toolkit.fluxcd.io/v2)
- Values are referenced from helmrelease.yaml via templating
- Chart sources must reference repos defined in `kubernetes/components/repos/`
- Use postBuild.substitute for environment-specific values
- **Auto-patched defaults** (only override if you need different behavior):
  - `driftDetection.mode: enabled`
  - `install.crds: CreateReplace`
  - `rollback.cleanupOnFail: true`, `rollback.recreate: true`
  - `upgrade.cleanupOnFail: true`, `upgrade.crds: CreateReplace`
  - `upgrade.strategy.name: RemediateOnFailure`
  - `upgrade.remediation.remediateLastFailure: true`, `upgrade.remediation.retries: 2`

### Talos Configuration

- Use `&anchors` in talconfig.yaml for node specs, patches, and labels
- Reference patches with `'@./patches/path/to/file.yaml'` syntax (glob patterns supported)
- Node names follow pattern: `kubernetes-{h1-h3}` (controllers), `kubernetes-h4` & `kubernetes-{l1-l3}` (workers)
- `kubernetes-hN` means `hp` based node, `kubernetes-lN` means `lenovo` based node
- Hardware-specific labels and patches are defined as anchors: `&lenovoLabels`, `&hpPatches`

## Common Mistakes to Avoid

1. **Hardcoding values** instead of using PostBuild substitution in ks.yaml
2. **Duplicating code/config** - always prefer DRY (use YAML anchors, Kustomize components, shared patches, etc.)
3. **Missing namespace declarations** - always declare namespace at category level
4. **Incorrect path references** - use relative paths (`../../../../components/`) consistently
5. **Forgetting dependsOn** - declare explicit dependencies for proper deployment ordering
6. **Modifying generated files** - clusterconfig/* files are generated by talhelper, edit talconfig.yaml instead, and let the generation process handle the rest
7. **Inconsistent naming** - all apps lowercase with hyphens, no underscores
8. **Missing schema validation** - add `# yaml-language-server: $schema=` comments for CRD validation

## GitOps Practices

- **Single source of truth**: All state declared in git, no manual cluster changes
- **Flux reconciliation**: All apps deployed via Flux Kustomization CRDs
- **Source reference**: All ks.yaml files reference `sourceRef: flux-system` (implicit)
- **Namespace management**: Flux Kustomization CRDs automatically create namespaces via `metadata.namespace` + `spec.targetNamespace`
- **Interval management**: Set appropriate reconciliation intervals (1h typical for app deployments)

## File Location Conventions

- **Namespace level**: `kubernetes/kustomization.yaml` - Top-level kustomization
- **New apps**: Place in `kubernetes/apps/{category}/{app-name}/` with ks.yaml entry point + app/ subdirectory
- **Category-level ks.yaml**: `kubernetes/apps/{category}/ks.yaml` - Contains multiple Flux Kustomization documents
- **App resources**: `kubernetes/apps/{category}/{app-name}/app/kustomization.yaml` - Kubernetes resources
- **Shared components**: Add reusable logic to `kubernetes/components/`
- **Global patches**: Talos patches that apply everywhere go in `talos/patches/global/`
- **Scripts**: Bootstrap scripts in `bootstrap/`, sourcing common functions from `bootstrap/lib/common.sh`

## Bootstrap & Deployment Workflow

- Use `task` to run all cluster management tasks (talhelper, talos, kubernetes, bootstrap)
- Scripts include structured logging with `log <level> <msg> [key=value ...]`
- Configuration is applied via talosctl to all nodes sequentially
- All state is applied declaratively; the script determines current vs desired state

## Available Tasks

Run `task --list` to see all available tasks. Common tasks by category:

**Bootstrap** (`task bootstrap:*`)
- `task bootstrap:default` - Bootstrap Talos nodes and cluster apps
  - **ONLY EVER RUN THIS WHEN EXPLICITLY REQUESTED BY USER** - this is the main entry point for bootstrapping the cluster, and it will apply all Talos configs and Kubernetes manifests. Use with caution, and only when you understand the implications of applying all changes at once.

**Talos** (`task talos:*`)
- `task talos:generate-config` - Generate Talos configuration from talconfig.yaml
- `task talos:apply-node IP=<node-ip>` - Apply Talos config to a specific node
- `task talos:apply-cluster` - Apply Talos config across the whole cluster
- `task talos:upgrade-node IP=<node-ip>` - Upgrade Talos on a single node (drains workloads first, **mandates reboot** - only run if required)
- `task talos:reboot-node IP=<node-ip>` - Reboot Talos on a single node
- `task talos:shutdown-cluster` - Shutdown entire Talos cluster

**Kubernetes** (`task kubernetes:*`)
- `task kubernetes:browse-pvc NS=<namespace> CLAIM=<name>` - Mount a PVC to a temp container
- `task kubernetes:node-shell NODE=<node-name>` - Open a shell to a node
- `task kubernetes:sync-secrets` - Sync all ExternalSecrets
- `task kubernetes:cleanse-pods` - Delete pods in Failed/Pending/Succeeded phases

**VolSync** (`task volsync:*`)
- Utility tasks for managing VolSync snapshots and replication

## Tool-Specific Guidance

### Kustomize
- Use `kustomization.yaml` for K8s resource overlays
- Reference external components via relative paths
- Use namespace field consistently

### Helm
- **After bootstrap**, all Helm charts are deployed via Flux HelmRelease CRDs (never direct `helm install/upgrade`)
- Charts referenced via OCI or repo sources in components/repos/
- Values inlined via template functions (not separate values files per app typically)
- Chart versions pinned for reproducibility
- **During bootstrap only**: Helm is deployed via helmfile (`bootstrap/helmfile.d/`) for initial cluster setup

### Flux (FluxCD)
- Kustomization CRD interval: reconciliation frequency (e.g., 1h)
- Kustomize.toolkit.fluxcd.io/v1 is the resource type
- All app deployments go through Flux, no direct deployments

### Talos
- talhelper generates cluster configs from talconfig.yaml
- talconfig.yaml is the single source of truth
- Patches are composable and applied per machine or globally

### Networking
- Always use HTTPRoutes, never use Ingress
- HTTPRoutes are the modern, standardized way to manage ingress traffic in this cluster
- Available Gateways: `internal` (default), `external` (only when app should be publicly accessible and security is not a concern)
- If an app has a HTTPRoute and does not support native authentication (such as oauth), add `../../../../components/ext-auth` as a component in `ks.yaml`

### Storage & Persistence
- If the app has storage that should be backed up and restored if the cluster were to fail, add `../../../../components/volsync` as a `ks.yaml` component
- VolSync component enables snapshot-based backup and restoration of persistent volumes, ensuring data recovery in case of cluster failure

## Cluster Components & Best Practices

### Timezones
- Always set timezones via `k8tz` and never manually
- This ensures consistent timezone handling across all workloads

### Configuration & Secret Management
- **Reloader**: Automatically restarts deployments when `ConfigMaps` or `Secrets` change
  - Add annotation `reloader.stakater.com/auto: "true"` to ensure pods restart when dependencies change
- **External Secrets**: Use for all in-repository secrets; never use sops
  - Always reference `secretStoreRef: bitwarden`
  - Example:
    ```yaml
    ---
    # yaml-language-server: $schema=https://schemas.tholinka.dev/external-secrets.io/externalsecret_v1.json
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: &secret cnpg-objectstore-substitute
    spec:
      secretStoreRef:
        kind: ClusterSecretStore
        name: bitwarden
      target:
        name: *secret
        template:
          data:
            S3_POSTGRES_STORAGE: '{{ .S3_POSTGRES_STORAGE }}'
            S3_POSTGRES_BUCKET: '{{ .S3_POSTGRES_BUCKET }}'
      dataFrom:
        - extract:
            key: cloudnative_pg
    ```

### Certificates
- **cert-manager**: Use for all certificate management
- Handles automatic certificate provisioning and renewal

### Monitoring & Alerting
- **PrometheusRule**: Use for creating alerts based on Prometheus metrics
- Defines alert rules and recording rules for cluster monitoring

### Scaling
- **KEDA**: Use for autoscaling pod replicas based on metrics and events
- Configure scalers appropriate to your application needs

### Databases
- **PostgreSQL**: Primary SQL database via `postgres-cluster-rw.database.svc.cluster.local`
  - Use `components/cnpg/app` or `components/cnpg/app-template` for DRY implementation
  - Always add the app's database role to `cluster.yaml`
- **Dragonfly**: Use instead of Redis or Valkey
  - Use `components/dragonfly/<TYPE>` for DRY implementation
  - Read the `components/dragonfly` README to determine which type to use

### Messaging
- **VerneMQ**: Cluster's MQTT broker
  - Always use instead of alternatives like Mosquitto

### GPU Resources
- **intel-gpu-resource-driver**: Handles all GPU-related configuration
- Use `resourceClaims` in pod spec and create a `resourceClaimTemplate` when needing GPU access

## Validation & Schema

Include schema validation comments for IDE support:
```yaml
# yaml-language-server: $schema=https://json.schemastore.org/kustomization.json
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
```

**When selecting schema URLs, prefer in this order:**
1. Official schemas from GitHub (e.g., FluxCD, Kustomize)
2. Schemas available at `json.schemastore.org`
3. Schemas at `schemas.tholinka.dev` with format: `schemas.tholinka.dev/<CRD_GROUP>/<CRD_KIND>_<CRD_VERSION>.json`
   - Note: These schemas are automatically uploaded from the running cluster and may only exist after the CRD is deployed

Always verify that the schema URL actually works before using it.

## When in Doubt

- Check existing apps in the same category for patterns (e.g., look at `kubernetes/apps/self-hosted/homepage/` for reference)
- Review talconfig.yaml anchors and patches for Talos configurations
- See Helm section above for how Helm is deployed (via Flux HelmRelease CRDs post-bootstrap, or helmfile during bootstrap only)
- Ensure all paths use consistent relative path format
