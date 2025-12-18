## 🛜 Networking

### DNS

> [!IMPORTANT]
>
> In the Unifi Network App: under Settings:
>  1) Under Network -> IPv6 -> Additional IPs, add the ULA IP for that network, e.g. `fdaa:aaaa:aaaa:5::1/64`
> 2) Under Policy Table -> Create New Policy -> NAT -> Src NAT -> Select network -> IPv6 -> select ULA
> > RIP Hardware Acceleration with IPv6 NAT enabled

### UniFi BGP Setup

Verify it's working with `vtysh -c 'show bgp ipv4' ; vtysh -c 'show bgp ipv6'`.

```conf
! -*- bgp -*-
!
frr defaults traditional
!
router bgp 64513
  bgp router-id 192.168.5.1
  no bgp ebgp-requires-policy
  maximum-paths 9

  neighbor k8s-v4 peer-group
  neighbor k8s-v4 remote-as 64514

  bgp listen range 192.168.20.0/24 peer-group k8s-v4

  address-family ipv4 unicast
    neighbor k8s-v4 next-hop-self
    neighbor k8s-v4 soft-reconfiguration inbound
  exit-address-family
  !

  neighbor k8s-v6 peer-group
  neighbor k8s-v6 remote-as 64514

  bgp listen range fdaa:aaaa:aaaa:20::/64 peer-group k8s-v6

  address-family ipv6 unicast
    neighbor k8s-v6 activate
    neighbor k8s-v6 next-hop-self
    neighbor k8s-v6 soft-reconfiguration inbound
    neighbor k8s-v6 maximum-prefix 256
  exit-address-family
  !
route-map ALLOW-ALL permit 10
!
line vty
!
```

### Healthchecks.io ping

SSH into router, then run:

>[!NOTE]
> This installs the on boot script, and then sets up the healthchecks.io ping.
>
> You can leave the `05-` and `06-` scripts that are installed by default if you use them, I don't.

```sh
curl -fsL "https://raw.githubusercontent.com/unifi-utilities/unifios-utilities/HEAD/on-boot-script-2.x/remote_install.sh" | /bin/bash
rm /data/on_boot.d/05-install-cni-plugins.sh
rm /data/on_boot.d/06-cni-bridge.sh
URL=https://hc-ping.com/example-uuid
cat > /data/on_boot.d/20-healthchecksio.sh << EOF
#!/bin/sh
echo '* * * * * root curl -X POST $URL' > /etc/cron.d/healthchecksio
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
