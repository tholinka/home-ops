---
apiVersion: v1alpha1
kind: UnattendedInstallConfig
provisioning:
  diskSelector:
    match: {{ .Node.Data.disk }}
  wipe: false
