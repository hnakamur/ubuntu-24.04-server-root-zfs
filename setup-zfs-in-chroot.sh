#!/bin/bash -x
set -eu

apt-get update
locale-gen --purge en_US.UTF-8 ja_JP.UTF-8
DEBIAN_FRONTEND=noninteractive apt-get install --yes vim

ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

# Create the EFI filesystem:
DEBIAN_FRONTEND=noninteractive apt-get install --yes dosfstools

mkdosfs -F 32 -s 1 -n EFI "${DISK_PART}1"
sync
sleep 5

mkdir /boot/efi
echo /dev/disk/by-uuid/$(blkid -s UUID -o value "${DISK_PART}1") \
    /boot/efi vfat defaults 0 0 >> /etc/fstab
mount /boot/efi

# Put /boot/grub on the EFI System Partition:
mkdir /boot/efi/grub /boot/grub
echo /boot/efi/grub /boot/grub none defaults,bind 0 0 >> /etc/fstab
mount /boot/grub

# create directories to avoid the following message:
# info: The home dir /var/lib/usbmux you specified can't be accessed: No such file or directory
# ERROR couldn't connect to zsys daemon: connection error: desc = "transport: Error while dialing: dial unix /run/zsysd.sock: connect: no such file or directory"                                                           (Reading database ... 29679 files and directories currently installed.)
# Failed to open connection to "system" message bus: Failed to connect to socket /run/dbus/system_bus_socket: No such file or directory
# invoke-rc.d: initscript dbus, action "reload" failed.
# start-stop-daemon: unable to stat /usr/libexec/polkitd (No such file or directory)
#mkdir -p /var/lib/usbmux /run/dbus /usr/libexec

# Install GRUB/Linux/ZFS for UEFI booting:
DEBIAN_FRONTEND=noninteractive apt-get install --yes \
    grub-efi-amd64 grub-efi-amd64-signed linux-image-generic \
    shim-signed zfs-initramfs zsys

apt purge --yes os-prober

echo "root:$ROOT_PASSWORD" | chpasswd

mkswap -f "${DISK_PART}2"
sync
sleep 5
echo /dev/disk/by-uuid/$(blkid -s UUID -o value "${DISK_PART}2") \
    none swap discard 0 0 >> /etc/fstab
swapon -a

cp /usr/share/systemd/tmp.mount /etc/systemd/system/
systemctl enable tmp.mount

DEBIAN_FRONTEND=noninteractive apt-get install --yes openssh-server
if [ -n "$SSH_PUB_KEY_URL" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install --yes curl
    curl -sSLo /root/.ssh/authorized_keys "$SSH_PUB_KEY_URL"
    chmod 600 /root/.ssh/authorized_keys
else
    sed '/^#PermitRootLogin prohibit-password/a\
PermitRootLogin yes
' /etc/ssh/sshd_config
fi

grub-probe /boot

update-initramfs -c -k all

sed -i.orig 's/^GRUB_TIMEOUT_STYLE=hidden/#&/
s/^\(GRUB_TIMEOUT=\).*/\1=5/
/^GRUB_TIMEOUT=/a\
GRUB_RECORDFAIL_TIMEOUT=5
s/^\(GRUB_CMDLINE_LINUX_DEFAULT=\)"quiet splash"/\1""/
s/^#\(GRUB_TERMINAL=console\)/\1/
' /etc/default/grub

update-grub

grub-install --target=x86_64-efi --efi-directory=/boot/efi \
    --bootloader-id=ubuntu --recheck --no-floppy

mkdir /etc/zfs/zfs-list.cache
touch /etc/zfs/zfs-list.cache/bpool
touch /etc/zfs/zfs-list.cache/rpool
zed -F &

sync
sleep 5

cat /etc/zfs/zfs-list.cache/bpool
cat /etc/zfs/zfs-list.cache/rpool

kill %1

sed -Ei "s|/mnt/?|/|" /etc/zfs/zfs-list.cache/*
