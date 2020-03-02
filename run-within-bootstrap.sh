#/bin/bash
# chroot image create
dd if=/dev/null of=/hdd.image bs=1 count=0 seek=$IMAGE_SIZE &&
echo -e "n\np\n\n\n+${BOOT_PARTITION_SIZE}\nn\np\n\n\n+${SWAP_PARTITION_SIZE}\nn\np\n\n\n\nt\n2\n82\nw\n" | fdisk /hdd.image &&
(losetup -d /dev/loop0 || echo ignored) &&
losetup -P /dev/loop0 /hdd.image &&
mkfs.ext2 /dev/loop0p1 &&
mkswap /dev/loop0p2 &&
mkfs.ext4 /dev/loop0p3 &&
mount /dev/loop0p3 /mnt &&
ln -s ../../loop0p1 /dev/disk/by-uuid/$(blkid -s UUID -o value /dev/loop0p1) &&
ln -s ../../loop0p2 /dev/disk/by-uuid/$(blkid -s UUID -o value /dev/loop0p2) &&
ln -s ../../loop0p3 /dev/disk/by-uuid/$(blkid -s UUID -o value /dev/loop0p3) &&
mkdir -p /mnt/boot &&
mount /dev/loop0p1 /mnt/boot &&
pacman-key --init &&
pacman-key --populate archlinux &&
pacstrap /mnt base &&
swapon /dev/loop0p2 &&
genfstab -U /mnt | awk '! /\/swap/' > /mnt/etc/fstab &&
swapoff /dev/loop0p2 &&
mkdir -p /mnt/root/run-within-image &&
mount --bind /root/run-within-image /mnt/root/run-within-image &&
arch-chroot /mnt /root/run-within-image/run-within-image.sh &&
umount /mnt/root/ &&
umount /dev/loop0p1 &&
umount /dev/loop0p3 &&
rm -f /dev/disk/by-uuid/{$(blkid -s UUID -o value /dev/loop0p1), $(blkid -s UUID -o value /dev/loop0p2), $(blkid -s UUID -o value /dev/loop0p3)} &&
losetup -d /dev/loop0
