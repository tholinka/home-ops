---
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: nut-client
configFiles:
  - content: |-
      MONITOR cluster@pikvm.servers.internal 1 {{ .Data.nutUsername }} "{{ .Data.nutPassword }}" secondary
      SHUTDOWNCMD "/sbin/poweroff"
    mountPath: /usr/local/etc/nut/upsmon.conf
