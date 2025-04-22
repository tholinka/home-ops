# Dragonfly

### HealthChecks

```yaml
  components:
    - ../../../../components/cnpg/backup
  healthChecks:
    - apiVersion: &dragonflyVersion dragonflydb.io/v1alpha1
      kind: &dragonflyKind Dragonfly
      name: APPNAME-dragonfly
      namespace: *namespace
  healthCheckExprs:
    - apiVersion: *dragonflyVersion
      kind: *dragonflyKind
      failed: status.phase != 'ready'
      current: status.phase == 'ready'
```
