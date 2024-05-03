#!/bin/bash -x

if [ -z "$HOSTNAME" ]; then
    >&2 echo HOSTNAME environment variable must be set.
    exit 2
fi
if [ -z "$ROOT_PASSWORD" ]; then
    >&2 echo ROOT_PASSWORD environment variable must be set.
    exit 2
fi
if [ -z "$DISK" ]; then
    >&2 echo DISK environment variable must be set.
    exit 2
fi

ROOT_PART_SIZE=${ROOT_PART_SIZE:-0}

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --yes debootstrap gdisk zfsutils-linux vim
systemctl stop zed

wipefs -a $DISK
sgdisk -n1:1M:+512M -t1:EF00 $DISK
sgdisk -n2::+2G -t2:8200 $DISK
sgdisk -n3::+2G -t3:BE00 $DISK
sgdisk -n4::$ROOT_PART_SIZE -t4:8309 $DISK

if [ -z "$DISK_PART" ]; then
    if [ -e "${DISK}1" ]; then
        DISK_PART="${DISK}"
    elif [ -e "${DISK}p1" ]; then
        DISK_PART="${DISK}p"
    elif [ -e "${DISK}-part1" ]; then
        DISK_PART="${DISK}-part"
    else
        >&2 echo cannot detect DISK_PART from DISK environment variable.
        exit 2
    fi
fi

sync
sleep 5

zpool create \
    -o ashift=12 \
    -o autotrim=on \
    -o cachefile=/etc/zfs/zpool.cache \
    -o compatibility=grub2 \
    -o feature@extensible_dataset=disabled \
    -o feature@bookmarks=disabled \
    -o feature@filesystem_limits=disabled \
    -o feature@large_blocks=disabled \
    -o feature@large_dnode=disabled \
    -o feature@sha512=disabled \
    -o feature@skein=disabled \
    -o feature@edonr=disabled \
    -o feature@userobj_accounting=disabled \
    -o feature@encryption=disabled \
    -o feature@project_quota=disabled \
    -o feature@obsolete_counts=disabled \
    -o feature@bookmark_v2=disabled \
    -o feature@redaction_bookmarks=disabled \
    -o feature@redacted_datasets=disabled \
    -o feature@bookmark_written=disabled \
    -o feature@livelist=enabled \
    -o feature@zstd_compress=disabled \
    -o feature@zilsaxattr=disabled \
    -o feature@head_errlog=disabled \
    -o feature@blake3=disabled \
    -o feature@vdev_zaps_v2=disabled \
    -o feature@zpool_checkpoint=enabled \
    -O devices=off \
    -O acltype=posixacl -O xattr=sa \
    -O compression=off \
    -O normalization=formD \
    -O relatime=on \
    -O canmount=off -O mountpoint=/boot -R /mnt -f \
    bpool "${DISK_PART}3"

zpool create \
    -o ashift=12 \
    -o autotrim=on \
    -O acltype=posixacl -O xattr=sa -O dnodesize=auto \
    -O compression=off \
    -O normalization=formD \
    -O relatime=on \
    -O canmount=off -O mountpoint=/ -R /mnt \
    rpool "${DISK_PART}4"

zfs create -o canmount=off -o mountpoint=none rpool/ROOT
zfs create -o canmount=off -o mountpoint=none bpool/BOOT

zfs create -o mountpoint=/ \
    -o com.ubuntu.zsys:bootfs=yes \
    -o com.ubuntu.zsys:last-used=$(date +%s) rpool/ROOT/ubuntu

zfs create -o mountpoint=/boot bpool/BOOT/ubuntu

zfs create -o com.ubuntu.zsys:bootfs=no -o canmount=off \
    rpool/ROOT/ubuntu/usr
zfs create -o com.ubuntu.zsys:bootfs=no -o canmount=off \
    rpool/ROOT/ubuntu/var
zfs create rpool/ROOT/ubuntu/var/lib
zfs create rpool/ROOT/ubuntu/var/log
zfs create rpool/ROOT/ubuntu/var/spool

zfs create -o canmount=off -o mountpoint=/ \
    rpool/USERDATA
zfs create -o com.ubuntu.zsys:bootfs-datasets=rpool/ROOT/ubuntu \
    -o canmount=on -o mountpoint=/root \
    rpool/USERDATA/root
chmod 700 /mnt/root

zfs create rpool/ROOT/ubuntu/var/cache
zfs create rpool/ROOT/ubuntu/var/tmp
chmod 1777 /mnt/var/tmp

zfs create rpool/ROOT/ubuntu/var/lib/apt
zfs create rpool/ROOT/ubuntu/var/lib/dpkg

zfs create rpool/ROOT/ubuntu/usr/local
zfs create rpool/ROOT/ubuntu/var/snap

zfs create rpool/ROOT/ubuntu/var/lib/docker
zfs create rpool/ROOT/ubuntu/var/www

mkdir /mnt/run
mount -t tmpfs tmpfs /mnt/run
mkdir /mnt/run/lock

debootstrap noble /mnt

mkdir /mnt/etc/zfs
cp /etc/zfs/zpool.cache /mnt/etc/zfs/

hostname "$HOSTNAME"
hostname > /mnt/etc/hostname
echo -e "127.0.0.1\\t$HOSTNAME" >> /mnt/etc/hosts

if [ -z "$IFACE" ]; then
    IFACE=$(ip -br link show | grep -o '^en[^ ]*')
fi
cat > /mnt/etc/netplan/99-config.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: true
EOF

cat > /mnt/etc/apt/sources.list <<'EOF'
# Ubuntu sources have moved to the /etc/apt/sources.list.d/ubuntu.sources
# file, which uses the deb822 format. Use deb822-formatted .sources files
# to manage package sources in the /etc/apt/sources.list.d/ directory.
# See the sources.list(5) manual page for details.
EOF

cp /etc/apt/sources.list.d/ubuntu.sources /mnt/etc/apt/sources.list.d/

mount --make-private --rbind /dev  /mnt/dev
mount --make-private --rbind /proc /mnt/proc
mount --make-private --rbind /sys  /mnt/sys

cp /tmp/setup-zfs-in-chroot.sh /mnt/tmp/

chroot /mnt /usr/bin/env \
    DISK_PART="$DISK_PART" SSH_PUB_KEY_URL="$SSH_PUB_KEY_URL" ROOT_PASSWORD="$ROOT_PASSWORD" \
    bash --login \
    -x /tmp/setup-zfs-in-chroot.sh

mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | \
    xargs -i{} umount -lf {}
zpool export -a || :
poweroff
