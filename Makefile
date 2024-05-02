ISO_FILENAME ?= ubuntu-24.04-live-server-amd64.iso
VM_NAME ?= numbatserver
HOSTNAME ?= sunshine-03
DISK ?= /dev/vda
ROOT_PASSWORD ?= root
SSH_PUB_KEY_URL ?= https://github.com/hnakamur.keys

# See
# https://gihyo.jp/admin/serial/01/ubuntu-recipe/0441
# for using UEFI firmware in QEMU/KVM.

boot_from_cdrom:
	sudo qemu-img create -f qcow2 /var/lib/libvirt/images/${VM_NAME}.qcow2 25G
	sudo apt-get install --yes ovmf
	cp /usr/share/OVMF/OVMF_VARS.fd OVMF_VARS.fd
	sudo qemu-system-x86_64 -drive file=/var/lib/libvirt/images/${VM_NAME}.qcow2,if=virtio \
		-m 4096 -smp 2 -net nic -net bridge,br=virbr0 -enable-kvm \
		-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
		-drive if=pflash,format=raw,file=OVMF_VARS.fd \
		-boot d -cdrom $$PWD/${ISO_FILENAME}

install:
	if [ -z ${IP} ]; then \
		>&2 echo Please set IP environment variable.; \
		exit 2; \
	fi
	rsync -av -e 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' \
		install-zfs-server.sh setup-zfs-in-chroot.sh root@${IP}:/tmp/
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${IP} \
		HOSTNAME=${HOSTNAME} DISK=${DISK} \
		ROOT_PASSWORD=${ROOT_PASSWORD} SSH_PUB_KEY_URL=${SSH_PUB_KEY_URL} \
		/tmp/install-zfs-server.sh 2>&1 | tee install-$$(date +%Y%m%dT%H%M%S).log

ssh:
	if [ -z ${IP} ]; then \
		>&2 echo Please set IP environment variable.; \
		exit 2; \
	fi
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${IP} \
		HOSTNAME=${HOSTNAME} DISK=${DISK} \
		ROOT_PASSWORD=${ROOT_PASSWORD} SSH_PUB_KEY_URL=${SSH_PUB_KEY_URL} \

boot_from_disk:
	sudo qemu-system-x86_64 -drive file=/var/lib/libvirt/images/${VM_NAME}.qcow2,if=virtio \
		-m 4096 -smp 2 -net nic -net bridge,br=virbr0 -enable-kvm \
		-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
		-drive if=pflash,format=raw,file=OVMF_VARS.fd \

clean:
	sudo virsh destroy ${VM_NAME}
	sudo virsh undefine ${VM_NAME}
	sudo rm /var/lib/libvirt/images/${VM_NAME}.qcow2

.PHONY: boot_from_cdrom install ssh boot_from_disk clean
