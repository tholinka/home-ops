# cloudnative-pg

## Postgres Clusters

- `../../../../components/cnpg/backup` for db with backups
- `../../../../components/cnpg/restore` for restoring db from backup, can be used after initial backup bootstrap has occurred
- `../../../../components/cnpg/no-backup` for db with no backups

### Variables to set:

```yaml
  dependsOn:
    - name: cnpg-crds
      namespace: *namespace
    - name: openebs
      namespace: openebs-system
  postBuild:
    substitute:
      APP: *app # required
      CNPG_REPLICAS: '1 '# default
      CNPG_IMAGE: ghcr.io/cloudnative-pg/postgresql:17.6-standard-trixie@sha256:e185037ad4c926fece1d3cfd1ec99680a862d7d02b160354e263a04a2d46b5f5 # required
      CNPG_SIZE: 2Gi # default
      CNPG_STORAGECLASS: openebs-hostpath # default
      CNPG_REQUESTS_CPU: 500m # default
      CNPG_LIMITS_MEMORY: 2Gi # default
      CNPG_MAX_CONNECTIONS: '600' # default
      CNPG_SHARED_BUFFERS: 512MB # default
      CNPG_DISABLED_SERVICES: ['ro', 'r'] # default
    subsituteFrom:
      # backup/restore requires:
      #S3_POSTGRES_STORAGE: https://s3.url
      #S3_POSTGRES_BUCKET: postgres
      # which is provided by a secret in cnpg-crds
      - kind: Secret
        name: cnpg-objectstore-substitute
        optional: false
```


### HealthChecks

```yaml
  healthChecks:
    - apiVersion: &postgresVersion postgresql.cnpg.io/v1
      kind: &postgresKind Cluster
      name: postgres-APPNAME
      namespace: *namespace
  healthCheckExprs:
    - apiVersion: *postgresVersion
      kind: *postgresKind
      failed: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'False')
      current: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'True')
```
