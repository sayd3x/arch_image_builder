#/bin/bash
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen &&
locale-gen &&
echo "LANG=en_US.UTF-8" > /etc/locale.conf &&
pacman -Sy --noconfirm grub sudo tar &&
echo "Installing pacman.packages..." &&
pacman -Sy --noconfirm - < $(dirname $0)/pacman.packages &&
echo "Installing extra packages..." &&
(cd $(dirname $0)/packages;[ -f binutils*.pkg.tar.xz ] && pacman -Rdd --noconfirm binutils) &&
(cd $(dirname $0)/packages;pacman -U --noconfirm *.pkg.tar.xz) &&
echo "Extracting config files..." &&
tar xJvf $(dirname $0)/image-root.tar.bz2 -C / &&
echo -e "${ROOT_PASSWD}\n${ROOT_PASSWD}" | passwd &&
echo "PermitRootLogin $PERMIT_ROOT_LOGIN" >> /etc/ssh/sshd_config &&
systemctl enable $AUTOSTART_SERVICES &&
sed -i "s/MODULES=()/MODULES=($INITRAMFS_MODULES)/g" /etc/mkinitcpio.conf &&
mkinitcpio -p linux &&
echo "Setup grub" &&
grub-install --target=i386-pc /dev/loop0 &&
grub-mkconfig -o /boot/grub/grub.cfg &&
echo "done"
