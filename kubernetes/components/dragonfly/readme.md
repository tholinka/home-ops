# Dragonfly

## HealthChecks

```yaml
  components:
    - ../../../../components/dragonfly/backup
  healthChecks:
    - apiVersion: &dragonflyVersion dragonflydb.io/v1alpha1
      kind: &dragonflyKind Dragonfly
      name: dragonfly-APPNAME
      namespace: *namespace
  healthCheckExprs:
    - apiVersion: *dragonflyVersion
      kind: *dragonflyKind
      failed: status.phase != 'ready' && status.phase != 'Ready'
      current: status.phase == 'ready' || status.phase == 'Ready'
```
