# cloudnative-pg

## Postgres Clusters

- `../../../../components/cnpg/backup` for db with backups
- `../../../../components/cnpg/restore` for restoring db from backup, can be used after initial backup bootstrap has occurred
- `../../../../components/cnpg/no-backup` for db with no backups

### Variables to set:

```yaml
  postBuild:
    substitute:
      APP: *app # required
      CNPG_REPLICAS: '1 '# default
      CNPG_IMAGE: ghcr.io/cloudnative-pg/postgresql # default
       # renovate: datasource=docker depName=ghcr.io/cloudnative-pg/postgresql
      POSTGRES_VERSION: 17.4-bookworm # required
      CNPG_SIZE: 2Gi # default
      CNPG_STORAGECLASS: openebs-hostpath # default
      CNPG_REQUESTS_CPU: 500m # default
      CNPG_LIMITS_MEMORY: 2Gi # default
      CNPG_MAX_CONNECTIONS: '600' # default
      CNPG_SHARED_BUFFERS: 512MB # default

      # backup and restore
      CNPG_CLUSTER_CURRENT: v1 # default. MUST increment when restoring cluster!

      # restore
      CNPG_CLUSTER_PREVIOUS: v0 # default. MUST increment when restoring cluster!
```
