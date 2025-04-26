## 🛜 Networking

### DNS

> [!IMPORTANT]
> In the Unifi Network App, under Settings -> Internet -> WAN1 and WAN2. Set IPv4 dns to `192.168.20.6` and IPv6 to `fdaa:aaaa:aaaa:aa20::6`.

### UniFi IPv6 ULA setup

> [!NOTE]
> Consolidated from here: https://github.com/unifi-utilities/unifios-utilities/issues/104#issuecomment-2259534906

first, ssh into Unifi gateway: `root@192.168.1.1`

> [!NOTE]
> Configure your ssh cert/password in the UniFi Network App

```bash
curl -fsL "https://raw.githubusercontent.com/unifi-utilities/unifios-utilities/HEAD/on-boot-script-2.x/remote_install.sh" | /bin/bash
chmod -x /data/onboot.d0/5-install-cni-plugins.sh /data/onboot.d0/6-cni-bridge.sh

mkdir /data/ipv6-ula

tee /data/ipv6-ula/ensure-ula.sh << '_EOF'
#!/bin/bash

ULA_PREFIX="fdaa:aaaa:aaaa"

add_ula () {
  if [ -z "`ip address show dev $1 to $ULA_PREFIX:$2::/64`" ]
  then
    ip address add $ULA_PREFIX:$2::1/64 dev $1
  fi
}

add_ula br0 aa00
add_ula br20 aa20
add_ula br30 aa30

ADDEDDNSMASQ=0

# only add entry to dnsmasq config if it does not exist
add_dnsmasq () {
  conf=$(find /run/dnsmasq.conf.d/ -type f -name "*$1*IPV6.conf")
  if [ -z "`grep ra-names $conf`" ]
  then
    sed -i 's/ra-only/ra-names/g' $conf
    echo "Changed to ra-names"
    ADDEDDNSMASQ=1
  fi
}

#add_dnsmasq br0
#add_dnsmasq br20
#add_dnsmasq br30

# Use single brackets for compatibility
if [ "$ADDEDDNSMASQ" = "1" ]; then
  pkill dnsmasq
fi
_EOF

chmod a+x /data/ipv6-ula/ensure-ula.sh

tee /data/on_boot.d/17-ula.sh << '_EOF'
#!/bin/sh

echo "* * * * * root /bin/bash -c 'sh /data/ipv6-ula/ensure-ula.sh'" > /etc/cron.d/ula
_EOF

chmod a+x /data/on_boot.d/17-ula.sh
```

### UniFi BGP Setup

The Gateway Max doesn't support BGP... but we can work around that by using a FRR onboot script.

Guide followed from here, after already setting up the onboot utilities from the ULA setup: https://www.map59.com/ubiquiti-udm-running-bgp/.

Verify it's working with `vtysh -c 'show ip bgp'`.

`/etc/frr/bgpd.conf`
```conf
! -*- bgp -*-
!
hostname $UDMP_HOSTNAME
password zebra
frr defaults traditional
log file stdout
!
router bgp 64513
  bgp router-id 192.168.1.1
  no bgp ebgp-requires-policy

  neighbor k8s peer-group
  neighbor k8s remote-as 64514

  neighbor 192.168.20.51 peer-group k8s

  neighbor 192.168.20.61 peer-group k8s
  neighbor 192.168.20.62 peer-group k8s
  neighbor 192.168.20.63 peer-group k8s

  neighbor 192.168.20.71 peer-group k8s
  neighbor 192.168.20.72 peer-group k8s
  neighbor 192.168.20.73 peer-group k8s
  neighbor 192.168.20.74 peer-group k8s

  neighbor 192.168.20.101 peer-group k8s

  address-family ipv4 unicast
    neighbor k8s next-hop-self
    neighbor k8s soft-reconfiguration inbound
  exit-address-family
  !
route-map ALLOW-ALL permit 10
!
line vty
!
```

### Healthchecks.io ping

```sh
UUID=test
cat > /data/on_boot.d/20-healthchecksio.sh << EOF
#!/bin/sh

echo '* * * * * root curl -X POST https://hc-ping.com/${UUID}' > /etc/cron.d/healthchecksio
EOF
chmod a+x /data/on_boot.d/20-healthchecksio.sh
/data/on_boot.d/20-healthchecksio.sh
```

## 💥 Cluster Blew Up?

### 💣 Reset

There might be a situation where you want to destroy your Kubernetes cluster. The following command will reset your nodes back to maintenance mode, append `--force` to completely format your the Talos installation. Either way the nodes should reboot after the command has successfully ran.

```sh
task talos:reset # --force
```

### Bootstrap Talos, Kubernetes, and Flux

1. Install Talos:

    >[!NOTE]
     _It might take a while for the cluster to be setup (10+ minutes is normal). During which time you will see a variety of error messages like: "couldn't get current server API group list," "error: no matching resources found", etc. 'Ready' will remain "False" as no CNI is deployed yet. **This is a normal.** If this step gets interrupted, e.g. by pressing <kbd>Ctrl</kbd> + <kbd>C</kbd>, you likely will need to [reset the cluster](#-reset) before trying again_

    ```sh
    task talos:generate-config
    task bootstrap:talos
    ```

2. Push your changes to git:

    ```sh
    git add -A
    git commit -m "chore: add talhelper encrypted secret :lock:"
    git push
    ```

3. Install cilium, coredns, cert-manager, external-secrets, flux and sync the cluster to the repository state:

    ```sh
    task bootstrap:apps
    ```

5. Watch the rollout of your cluster happen:

    ```sh
    watch kubectl get pods --all-namespaces
    ```

### 🪝 Github Webhook

By default Flux will periodically check your git repository for changes. In order to have Flux reconcile on `git push` you must configure Github to send `push` events to Flux.

1. Obtain the webhook path:

    > [!NOTE]
    _Hook id and path should look like `/hook/12ebd1e363c641dc3c2e430ecf3cee2b3c7a5ac9e1234506f6f5f3ce1230e123`_

    ```sh
    kubectl -n flux-system get receiver github-receiver -o jsonpath='{.status.webhookPath}'
    ```

2. Piece together the full URL with the webhook path appended:

    ```text
    https://flux-webhook.${cloudflare.domain}/hook/12ebd1e363c641dc3c2e430ecf3cee2b3c7a5ac9e1234506f6f5f3ce1230e123
    ```

3. Navigate to the settings of your repository on Github, under "Settings/Webhooks" press the "Add webhook" button. Fill in the webhook URL and your `${github.webhook_token}` secret from the [secret](kubernetes/apps/flux-system/flux-operator/instance/github/webhooks/secret.sops.yaml), Content type: `application/json`, Events: Choose Just the push event, and save.

## 🛠️ Talos and Kubernetes Maintenance

### ⚙️ Updating Talos node configuration

> [!IMPORTANT]
> Ensure you have updated `talconfig.yaml` and any patches with your updated configuration. In some cases you **not only need to apply the configuration but also upgrade talos** to apply new configuration.

```sh
# (Re)generate the Talos config
task talos:generate-config
# Apply the config to the node
task talos:apply-node IP=? MODE=?
# e.g. task talos:apply-node IP=10.10.10.10 MODE=auto
```

### ⬆️ Updating Talos and Kubernetes versions

> [!IMPORTANT]
> Ensure the `talosVersion` and `kubernetesVersion` in `talconfig.yaml` are up-to-date with the version you wish to upgrade to.

The `system-upgrade-controller` should handle this now, just update the versions in its ks.yaml.

It is however a good idea to manually run apply-cluster afterward so the in cluster config update.

```sh
# Upgrade node to a newer Talos version
task talos:upgrade-node IP=?
# e.g. task talos:upgrade-node IP=10.10.10.10
```

```sh
# Upgrade cluster to a newer Kubernetes version
task talos:upgrade-k8s
# e.g. task talos:upgrade-k8s
```

## 🐛 Debugging

Below is a general guide on trying to debug an issue with an resource or application. For example, if a workload/resource is not showing up or a pod has started but in a `CrashLoopBackOff` or `Pending` state. Most of these steps do not include a way to fix the problem as the problem could be one of many different things.

1. Verify the Git Repository is up-to-date and in a ready state.

    ```sh
    flux get sources git -A
    ```

    Force Flux to sync your repository to your cluster:

    ```sh
    flux -n flux-system reconcile ks flux-system --with-source
    ```

2. Verify all the Flux kustomizations are up-to-date and in a ready state.

    ```sh
    flux get ks -A
    ```

3. Verify all the Flux helm releases are up-to-date and in a ready state.

    ```sh
    flux get hr -A
    kubectl get hr -A
    kubectl describe hr -n namespace release-name # look at the bottom, for the recent helm logs
    ```

4. Do you see the pod of the workload you are debugging?

    ```sh
    kubectl -n <namespace> get pods -o wide
    ```

5. Check the logs of the pod if its there.

    ```sh
    kubectl -n <namespace> logs <pod-name> -f
    ```

6. If a resource exists try to describe it to see what problems it might have.

    ```sh
    kubectl -n <namespace> describe <resource> <name>
    ```

7. Check the namespace events

    ```sh
    kubectl -n <namespace> get events --sort-by='.metadata.creationTimestamp'
    ```

Resolving problems that you have could take some tweaking of your YAML manifests in order to get things working, other times it could be a external factor like permissions on a NFS server. If you are unable to figure out your problem see the support sections below.
