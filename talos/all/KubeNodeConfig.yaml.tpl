---
apiVersion: v1alpha1
kind: KubeNodeConfig
nodeIP:
  validSubnets:
    - 192.168.20.0/24
    - {{ .Data.ipv6Prefix }}::/64
labels:
  cpu: '{{ .Node.Data.cpu }}'
  intel.feature.node.kubernetes.io/gpu: '{{ .Node.Data.gpu }}'
{{ if eq .Node.Role "control-plane" }}
  node.kubernetes.io/exclude-from-external-load-balancers:
    $patch: delete
taints:
  node-role.kubernetes.io/control-plane:
    $patch: delete
{{ end }}
