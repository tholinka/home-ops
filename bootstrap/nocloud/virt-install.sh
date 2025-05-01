#!/usr/bin/env bash
set -Eeuo pipefail


sudo mkdir -p /opt/kvms/pools/devel

scp talos/clusterconfig/kubernetes-q1.yaml nas.servers.internal:~/q1.yaml

sudo mv ~/q1.yaml /opt/kvms/user-data

cd /opt/kvms

echo "local-hostname: q1" > meta-data
cat > /opt/kvms/iso/network-config << EOF
version: 1
config:
   - type: physical
     name: eth0
     subnets:
        - type: static
          address: 192.168.20.101
          netmask: 255.255.255.0
          gateway: 192.168.20.1
EOF

genisoimage -output cidata.iso -V cidata -r -J user-data meta-data network-config

echo mv $TMPDIR /opt/kvms
curl -o /opt/kvms/nocloud-amd64.iso -Lv https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.10.0/nocloud-amd64.iso
curl -o /opt/kvms/nocloud-amd64-secureboot.iso -Lv https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.10.0/nocloud-amd64-secureboot.iso

cat > bridged.xml << EOF
<network>
    <name>bridged</name>
    <forward mode="bridge" />
    <bridge name="br0" />
</network>
EOF

echo sudo virsh net-define bridged.xml
echo sudo virsh net-start bridged
echo sudo virsh net-autostart bridged
echo sudo birsh pool-define-as devel dir --target /opt/kvms/pools/devel
echo sudo virsh pool-start devel
echo sudo virsh pool-autostart devel

sudo virt-install \
	--virt-type kvm --hvm \
	-n talos --ram 16384 --vcpus 4 --cpu host-passthrough \
	-c /opt/kvms/nocloud-amd64-secureboot.iso \
	--cloud-init user-data=./user-data,meta-data=./meta-data,network-config=./network-config \
	--boot uefi,loader_secure=yes \
	--os-variant linux2024 \
	--controller=scsi,model=virtio-scsi \
	--disk pool=devel,size=80,format=qcow2,bus=scsi,discard=unmap,cache=writeback,io=threads \
	-w network=bridged \
	--graphics none --console pty,target_type=serial \
	--host-device 07:00.0



# the secureboot keys get enrolled and that causes the vm to reboot and lose the iso's...
sudo virsh attach-disk talos /opt/kvms/cidata.iso sdb --type cdrom
sudo virsh attach-disk talos /opt/kvms/nocloud-amd64-secureboot.iso sdc --type cdrom
# then boot into firmware -> reset
# the secureboot image does not log to the console, you have to use talosctl to monitor it
# this approach causes the IP to not be set by the nocloud config for some reason...
