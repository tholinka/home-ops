---
machine:
  nodeLabels:
    cpu: '{{ .Node.Data.cpu }}'
    intel.feature.node.kubernetes.io/gpu: '{{ .Node.Data.gpu }}'
{{ if hasKey .Node.Data "encryption" }}
{{ if eq true .Node.Data.encryption }}
  systemDiskEncryption:
    ephemeral: &encrypt
      provider: luks2
      keys:
        - slot: 0
          tpm: {}
    state: *encrypt
{{ end }}
{{ end }}
  install:
  {{ if hasKey .Node.Data "installDisk" }}
      disk: {{ .Node.Data.installDisk }}
  {{ end }}
  {{ if hasKey .Node.Data "installDiskSelectorSerial" }}
    diskSelector:
      serial: {{ .Node.Data.installDiskSelectorSerial }}
  {{ end }}
  kubelet:
    nodeIP:
      validSubnets:
        - 192.168.20.0/24
        - {{ .Data.ipv6Prefix }}::/64
