#!/usr/bin/env bash
set -Eeuo pipefail


echo sudo mkdir -p /opt/kvms/pools/devel
cd /opt/kvms

echo "local-hostname: q1" > meta-data
cat > network-config << EOF
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

echo mv $TMPDIR /opt/kvms
echo curl -o /opt/kvms/nocloud-amd64.iso -LV https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.9.4/nocloud-amd64.iso

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

echo sudo virt-install \
	--virt-type kvm --hvm \
	-n talos --ram 16384 --vcpus 4 --cpu host-passthrough \
	-c /opt/kvms/nocloud-amd64.iso \
	--cloud-init meta-data=./meta-data,network-config=./network-config\
	--os-variant linux2024 \
	--controller=scsi,model=virtio-scsi \
	--disk pool=devel,size=80,format=qcow2,bus=scsi,discard=unmap,cache=writeback,io=threads \
	-w network=bridged \
	--graphics none --console pty,target_type=serial \
	--host-device 07:00.0
