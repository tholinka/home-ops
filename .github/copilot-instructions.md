---
description: >
  Guidelines for working with the home-ops Kubernetes project. Use when making changes to Kubernetes manifests, Talos configurations, bootstrap scripts, or Helm deployments. Focus on GitOps practices with Flux, proper Kustomization structure, Talos cluster management, and maintaining DRY principle throughout.
---

# home-ops Copilot Instructions

GitOps-managed Kubernetes homelab running Talos Linux. All infrastructure is declarative and managed through git. Flux CD reconciles the desired state from this repository.

---

## Project Layout

```
kubernetes/
├── flux/cluster/ks.yaml             # Flux entry point — points at kubernetes/apps/
├── apps/{category}/                  # One directory per namespace/category
│   ├── kustomization.yaml           # K8s Kustomization: sets namespace, lists app ks.yaml refs, includes components
│   └── {app}/
│       ├── ks.yaml                  # Flux Kustomization CRD(s) — entry point for this app
│       └── app/
│           ├── kustomization.yaml   # K8s Kustomization: lists the actual resources
│           ├── helmrelease.yaml     # Flux HelmRelease CRD
│           └── ...                  # PVCs, ExternalSecrets, ConfigMaps, etc.
├── components/                      # Reusable Kustomize Components (kind: Component)
│   ├── common/                      # Namespace creation, alerts, ExternalSecret for substitutions
│   ├── repos/app-template/          # OCIRepository for bjw-s app-template Helm chart
│   ├── volsync/                     # VolSync backup/restore (PVC + ReplicationSource/Destination)
│   ├── ext-auth/                    # Authentik external auth SecurityPolicy
│   ├── cnpg/{app,app-template}      # CloudNativePG database provisioning
│   ├── dragonfly/                   # Dragonfly (Redis alternative) — see its README for type selection
│   └── scaler/                      # HPA scale to zero variants (scales to zero if required service is missing) (instance, metrics, statefulset)
talos/
├── talconfig.yaml                   # Single source of truth — talhelper generates clusterconfig/ from this
├── talsecret.yaml                   # Encrypted secrets
├── patches/{global,controller}/     # Composable machine patches
└── clusterconfig/                   # GENERATED — never edit directly
bootstrap/
├── bootstrap-cluster.sh             # Main bootstrap entry point
├── lib/common.sh                    # Shared logging/talosctl helpers
└── helmfile.d/                      # Helmfile charts for initial bootstrap ONLY
```

---

## How Flux Discovers Apps

The reconciliation chain works as follows:

1. **`kubernetes/flux/cluster/ks.yaml`** — A Flux Kustomization pointing `path: ./kubernetes/apps` with patches that auto-apply HelmRelease defaults (drift detection, rollback, upgrade remediation) to all child Kustomizations.
2. **`kubernetes/apps/{category}/kustomization.yaml`** — A standard Kubernetes Kustomization (`kustomize.config.k8s.io/v1beta1`) that:
   - Sets `namespace:` for the category
   - Lists each app's `ks.yaml` as a resource
   - Includes shared components (typically `../../components/common` and `../../components/repos/app-template`)
3. **`kubernetes/apps/{category}/{app}/ks.yaml`** — One or more Flux Kustomization CRDs (`kustomize.toolkit.fluxcd.io/v1`). Simple apps have one document; complex apps (e.g., cnpg, envoy-gateway) use multiple `---`-separated documents for CRDs, operator, config, etc.
4. **`kubernetes/apps/{category}/{app}/app/kustomization.yaml`** — Standard Kubernetes Kustomization listing the actual resources (HelmRelease, PVCs, ExternalSecrets, etc.)

---

## Adding a New App

### 1. Create the app directory

```
kubernetes/apps/{category}/{app-name}/
├── ks.yaml
└── app/
    ├── kustomization.yaml
    └── helmrelease.yaml
```

### 2. Write the Flux Kustomization (`ks.yaml`)

```yaml
---
# yaml-language-server: $schema=https://schemas.tholinka.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app my-app
  namespace: &namespace self-hosted
spec:
  interval: 1h
  components:
    - ../../../../components/volsync # if app needs backup
    - ../../../../components/ext-auth # if app needs authentication
    - ../../../../components/cnpg/app # if app needs PostgreSQL
  dependsOn:
    - name: postgres-cluster # if using cnpg
      namespace: database
  path: ./kubernetes/apps/self-hosted/my-app/app
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

Key rules:

- Always set `APP: *app` in `postBuild.substitute` when using components
- Use `dependsOn` for anything the app requires at deploy time
- Components are referenced with relative paths from the ks.yaml location (`../../../../components/...`)
- `sourceRef` always points to `flux-system`

### 3. Write the app Kustomization (`app/kustomization.yaml`)

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrelease.yaml
```

### 4. Register the app in the category kustomization

Add `- ./{app-name}/ks.yaml` to the `resources:` list in `kubernetes/apps/{category}/kustomization.yaml`.

### 5. HelmRelease defaults (auto-patched — don't repeat these)

The cluster-level Flux Kustomization automatically patches every HelmRelease with:

- `driftDetection.mode: enabled`
- `install.crds: CreateReplace`
- `rollback: {cleanupOnFail: true, recreate: true}`
- `upgrade: {cleanupOnFail: true, crds: CreateReplace, strategy.name: RemediateOnFailure, remediation: {remediateLastFailure: true, retries: 2}}`

Only override these if you need different behavior.

---

## Naming Conventions

- **Categories/namespaces**: lowercase, descriptive (`media`, `network`, `home-automation`)
- **Apps**: lowercase with hyphens (`home-assistant`, `cloudflare-tunnel`)
- **PostBuild variables**: UPPERCASE (`APP`, `VOLSYNC_CAPACITY`)

---

## Namespaces

Each category directory maps to a namespace. The `common` component auto-creates the namespace resource.

| Namespace               | Purpose                                                          |
| ----------------------- | ---------------------------------------------------------------- |
| `actions-runner-system` | GitHub Actions self-hosted runners                               |
| `database`              | PostgreSQL (CNPG), Dragonfly, VerneMQ                            |
| `flux-system`           | Flux CD                                                          |
| `home-automation`       | Home Assistant, ESPHome, Zigbee, Z-Wave, go2rtc, Piper, Whisper  |
| `kube-system`           | Cilium, CoreDNS, metrics-server                                  |
| `media`                 | Plex, \*arr stack, qBittorrent, SABnzbd, etc.                    |
| `network`               | Pihole, Cloudflare Tunnel, dnscrypt-proxy, Envoy Gateway, Multus |
| `observability`         | Victoria Metrics stack, Grafana, Victoria Logs, Gatus            |
| `openebs-system`        | OpenEBS storage                                                  |
| `renovate`              | Dependency update automation                                     |
| `rook-ceph`             | Rook/Ceph distributed storage                                    |
| `security`              | Authentik, cert-manager, External Secrets                        |
| `self-hosted`           | Homepage, Immich, Paperless, ownCloud, Atuin, etc.               |
| `system`                | Reloader, Spegel, Descheduler, VolSync, Intel GPU driver         |
| `system-controllers`    | k8tz, snapshot-controller                                        |
| `system-upgrade`        | Tuppr (system upgrade controller)                                |

When adding a new app, choose the namespace that best matches its purpose. Review existing apps in the category for patterns.

---

## Shared Components (`kubernetes/components/`)

All components are Kustomize Components (`kind: Component`). They are referenced either from category-level `kustomization.yaml` or from app-level `ks.yaml` depending on scope.

| Component                         | Referenced from               | Purpose                                                                      |
| --------------------------------- | ----------------------------- | ---------------------------------------------------------------------------- |
| `common`                          | Category `kustomization.yaml` | Creates namespace, common alerts, substitution ExternalSecret                |
| `repos/app-template`              | Category `kustomization.yaml` | Provides the `app-template` OCIRepository                                    |
| `volsync`                         | App `ks.yaml`                 | PVC backup/restore via VolSync                                               |
| `ext-auth`                        | App `ks.yaml`                 | Authentik proxy auth SecurityPolicy                                          |
| `cnpg/app` or `cnpg/app-template` | App `ks.yaml`                 | PostgreSQL database provisioning                                             |
| `dragonfly/*`                     | App `ks.yaml`                 | Dragonfly instance (see `components/dragonfly/readme.md` for type selection) |
| `scaler/*`                        | App `ks.yaml`                 | HPA Scale to zero variants (`instance`, `metrics`, `statefulset`)            |

---

## Cluster Services & Conventions

### Networking

- **Always use HTTPRoutes**, never Ingress
- Available Gateways: `internal` (default), `external` (only for publicly accessible apps where security is not a concern)
- Apps with HTTPRoutes that lack native auth → add `../../../../components/ext-auth` in `ks.yaml`

### Storage

- **VolSync**: Add `../../../../components/volsync` to `ks.yaml` for any data that should survive cluster failure
- Set `VOLSYNC_CAPACITY` in `postBuild.substitute` if more than the default amount (`5Gi`) of backup storage is needed

### Databases

- **PostgreSQL**: Connect via `postgres-cluster-rw.database.svc.cluster.local`
  - Use `components/cnpg/app` (Helm chart) or `components/cnpg/app-template` (app-template chart)
  - Add the app's database role to `kubernetes/apps/database/cnpg/cluster/`
- **Dragonfly**: Use instead of Redis/Valkey — see `components/dragonfly/readme.md` for type selection

### Secrets

- **External Secrets** with Bitwarden — never use SOPS
  - Always use `secretStoreRef: {kind: ClusterSecretStore, name: bitwarden}`
- **Reloader**: Add annotation `reloader.stakater.com/auto: "true"` to restart pods when ConfigMaps/Secrets change

### Timezones

- Always handled by **k8tz** — never set TZ manually in pod specs

### GPU

- Use `resourceClaims` in pod spec + `resourceClaimTemplate` for Intel GPU access via `intel-gpu-resource-driver`

### Messaging

- **VerneMQ** is the cluster MQTT broker — always use it instead of Mosquitto or alternatives

### Monitoring

- **PrometheusRule** for alerts; **HorizontalPodAutoscaler** for autoscaling

### Certificates

- **cert-manager** handles all certificate provisioning and renewal

---

## Talos Configuration

`talos/talconfig.yaml` is the single source of truth. `talhelper` generates per-node configs into `clusterconfig/` — **never edit generated files**.

### Node inventory

| Hostname | IP            | Hardware               | Role       |
| -------- | ------------- | ---------------------- | ---------- |
| `l1`     | 192.168.20.61 | Lenovo M700 (i5-6400T) | Worker     |
| `l2`     | 192.168.20.62 | Lenovo M700 (i5-6400T) | Worker     |
| `l3`     | 192.168.20.63 | Lenovo M700 (i5-6400T) | Worker     |
| `h1`     | 192.168.20.71 | HP 800 G5 (i5-9500T)   | Controller |
| `h2`     | 192.168.20.72 | HP 400 G5 (i5-9500T)   | Controller |
| `h3`     | 192.168.20.73 | HP 400 G4 (i5-8500T)   | Controller |
| `h4`     | 192.168.20.74 | HP 400 G5 (i5-9500T)   | Worker     |

- `hN` = HP-based node, `lN` = Lenovo-based node
- Generated config filenames: `clusterconfig/kubernetes-{hostname}.yaml`

### Patterns

- YAML anchors for DRY: `&x64MachineSpec`, `&x64schematic`, `&extensionServices`, `&lenovoLabels`, `&hpLabels`, `&hpPatches`
- Patches referenced with `'@./patches/path/to/file.yaml'` syntax
- Global patches in `patches/global/`, controller-only patches in `patches/controller/`

---

## Available Tasks

Run `task --list` for the full list. Key tasks:

| Task                                              | Description                                   | Notes                                     |
| ------------------------------------------------- | --------------------------------------------- | ----------------------------------------- |
| `task bootstrap:default`                          | Bootstrap Talos nodes and cluster apps        | **⚠️ ONLY run when explicitly requested** |
| `task talos:generate-config`                      | Generate Talos configs from talconfig.yaml    |                                           |
| `task talos:apply-node IP=<ip>`                   | Apply Talos config to one node                |                                           |
| `task talos:apply-cluster`                        | Apply Talos config to all nodes               |                                           |
| `task talos:upgrade-node IP=<ip>`                 | Upgrade Talos on a node (drains + reboots)    | Only run if required                      |
| `task talos:upgrade-node IP=<ip>`                 | Upgrade Talos on all nodes (drains + reboots) | Only run if required                      |
| `task talos:reboot-node IP=<ip>`                  | Reboot a single node                          |                                           |
| `task talos:shutdown-cluster`                     | Shutdown entire cluster                       |                                           |
| `task kubernetes:browse-pvc NS=<ns> CLAIM=<name>` | Mount a PVC to a temp container               |                                           |
| `task kubernetes:node-shell NODE=<name>`          | Shell into a node                             |                                           |
| `task kubernetes:sync-secrets`                    | Force-sync all ExternalSecrets                |                                           |
| `task kubernetes:cleanse-pods`                    | Delete Failed/Pending/Succeeded pods          |                                           |
| `task reconcile`                                  | Force Flux to pull from git                   |                                           |

---

## Schema Validation

Always include `yaml-language-server` schema comments. Prefer schemas in this order:

1. Official schemas from upstream projects (e.g., FluxCD GitHub)
2. `json.schemastore.org`
3. `schemas.tholinka.dev/<CRD_GROUP>/<CRD_KIND>_<CRD_VERSION>.json` (auto-uploaded from cluster; may not exist until CRD is deployed)

Verify schema URLs resolve before using them.

---

## Common Mistakes

1. **Wrong file for the edit** — Category `kustomization.yaml` lists apps; app `ks.yaml` defines Flux behavior; app `app/kustomization.yaml` lists resources
2. **Hardcoding values** — Use `postBuild.substitute` in `ks.yaml`
3. **Repeating auto-patched HelmRelease defaults** — They're applied globally by `kubernetes/flux/cluster/ks.yaml`
4. **Editing `clusterconfig/` files** — Edit `talconfig.yaml` and run `task talos:generate-config`
5. **Missing `dependsOn`** — Declare dependencies for proper ordering (databases, storage, CRDs)
6. **Missing `APP` substitution** — Required when using any component
7. **Using Ingress** — Always use HTTPRoutes
8. **Manual TZ config** — k8tz handles it
9. **Missing schema comments** — Add `# yaml-language-server: $schema=` to all YAML files
10. **Forgetting to register the app** — Add the `ks.yaml` reference to the category `kustomization.yaml`

---

## When in Doubt

- Look at existing apps in the same category for patterns
- `kubernetes/apps/self-hosted/homepage/` is a good simple reference
- `kubernetes/apps/self-hosted/paperless/` shows a complex app (volsync + cnpg + dragonfly + HPA scale to zero)
- `kubernetes/apps/database/cnpg/ks.yaml` shows multi-document ks.yaml pattern
- Review `kubernetes/flux/cluster/ks.yaml` to understand auto-patching
- Check component READMEs (`components/dragonfly/readme.md`, `components/ext-auth/readme.md`)
