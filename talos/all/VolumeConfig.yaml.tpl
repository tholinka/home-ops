{{ if hasKey .Node.Data "encryption" }}
{{ if eq true .Node.Data.encryption }}
---
apiVersion: v1alpha1
kind: VolumeConfig
name: EPHEMERAL
encryption:
  allowDiscards: true
  provider: luks2
  keys:
  - slot: 0
    tpm: {}
  options:
    - no_read_workqueue
    - no_write_workqueue
---
apiVersion: v1alpha1
kind: VolumeConfig
name: STATE
encryption:
  allowDiscards: true
  provider: luks2
  keys:
  - slot: 0
    tpm: {}
  options:
    - no_read_workqueue
    - no_write_workqueue
{{ end }}
{{ end }}
