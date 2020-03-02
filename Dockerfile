FROM archlinux/base:latest as arch_builder

WORKDIR /root
ENV ROOT_DIR=/root/bootstrap
ENV BUILD_DIR=/tmp/build
ENV OUT_DIR=/tmp/packages
ENV PACKAGES_DIR=/root/bootstrap/root/run-within-image/packages

# Prepare bootstrap
RUN pacman -Sy --noconfirm awk sed tar && \
	mkdir $BUILD_DIR && \
	(cd $BUILD_DIR;curl -O https://mirror.yandex.ru/archlinux/iso/latest/md5sums.txt) && \
	BOOTSTRAP_IMAGE=$(cat $BUILD_DIR/md5sums.txt | awk '/archlinux-bootstrap/' | awk '{print $2}') && \
	BOOTSTRAP_IMAGE_CHECKSUM=$(cat $BUILD_DIR/md5sums.txt | awk '/archlinux-bootstrap/' | awk '{print $1}') && \
	(cd $BUILD_DIR;curl -O https://mirror.yandex.ru/archlinux/iso/latest/$BOOTSTRAP_IMAGE) && \
	[[ $(echo $BOOTSTRAP_IMAGE_CHECKSUM) == $(md5sum $BUILD_DIR/$BOOTSTRAP_IMAGE | awk '{print $1}') ]] && \
	tar xzf $BUILD_DIR/$BOOTSTRAP_IMAGE && \
	mv $PWD/root.* $ROOT_DIR && \
	sed -i '/^#.*yandex/s/^#//' $ROOT_DIR/etc/pacman.d/mirrorlist && \
	sed -i 's/\$(lsblk -rno UUID/$(blkid -s UUID -o value/g' $ROOT_DIR/sbin/genfstab && \ 
	sed -i 's/\$(lsblk -rno LABEL/$(blkid -s LABEL -o value/g' $ROOT_DIR/sbin/genfstab && \
	echo MAKEFLAGS=\"-j$(nproc)\" >> /etc/makepkg.conf && \
	rm -rf $BUILD_DIR && \
	rm -rf /var/cache/pacman/*

# Build & install yaourt
RUN cp -f $ROOT_DIR/etc/pacman.d/mirrorlist /etc/pacman.d/ && \
	pacman -Sy --noconfirm base-devel git && \
	echo "nobody ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
	mkdir -p $BUILD_DIR $OUT_DIR $PACKAGES_DIR && \
	chmod 777 -R $BUILD_DIR $OUT_DIR && \
	(cd $BUILD_DIR;curl https://aur.archlinux.org/cgit/aur.git/snapshot/package-query.tar.gz | sudo -u nobody tar xzf -;cd ./package-query;sudo -u nobody HOME=$BUILD_DIR PKGDEST=$OUT_DIR makepkg -si --noconfirm) && \
	(cd $BUILD_DIR;curl https://aur.archlinux.org/cgit/aur.git/snapshot/yaourt.tar.gz | sudo -u nobody tar xzf -;cd ./yaourt;sudo -u nobody HOME=$BUILD_DIR PKGDEST=$OUT_DIR makepkg -si --noconfirm) && \
	cp -r $OUT_DIR/*.pkg.tar.xz $PACKAGES_DIR/ && \
	rm -rf $BUILD_DIR $OUT_DIR /var/cache/pacman/*


ENV ROOT_PASSWD=change_me
ENV PERMIT_ROOT_LOGIN=yes
ENV IMAGE_SIZE=17G
ENV BOOT_PARTITION_SIZE=500M
ENV SWAP_PARTITION_SIZE=4G
ENV INITRAMFS_MODULES="ahci crc16 dm-cache dm-persistent-data ehci-pci hid-generic libcrc32c pata_acpi sr_mod ata_generic crc32c_generic dm-cache-smq dm-region-hash ext4 i8042 libps2 scsi_mod usb-common ata_piix crc32c-intel dm-log dm-snapshot floppy jbd2 mbcache sd_mod usbcore atkbd dm-bio-prison dm-mirror dm-thin-pool libahci ohci-hcd serio usbhid cdrom dm-bufio dm-mod ehci-hcd hid libata ohci-pci serio_raw usb-storage"
ENV AUTOSTART_SERVICES="ntpd.service sshd.service haveged.service docker.service xlogin@root.service"

COPY ./start.sh 				/root/
COPY ./run-within-bootstrap.sh 	/root/bootstrap/root/
COPY ./run-within-image.sh 		/root/bootstrap/root/run-within-image/
COPY ./image-root.tar.bz2 		/root/bootstrap/root/run-within-image/
COPY ./pacman.packages 			/root/bootstrap/root/run-within-image/
COPY ./extra-packages			/root/bootstrap/root/run-within-image/packages

FROM arch_builder as archminer_builder

# Build & install nvidia-docker
ADD ./nvidia-docker.tar.gz /tmp/build
RUN	pacman -Sy --noconfirm docker go && \
	mkdir -p $OUT_DIR && \
	chmod 777 -R $BUILD_DIR $OUT_DIR && \
	(cd $BUILD_DIR;sudo -u nobody HOME=$BUILD_DIR yaourt -S --noconfirm --export $OUT_DIR nvidia-container-runtime) && \
	(cd $BUILD_DIR/nvidia-docker;sudo -u nobody HOME=$BUILD_DIR PKGDEST=$OUT_DIR makepkg -si --noconfirm) && \
	pacman -Rcns --noconfirm docker go && \
	cp -r $OUT_DIR/*.pkg.tar.xz $PACKAGES_DIR/ && \
	rm -rf $BUILD_DIR $OUT_DIR /var/cache/pacman/*

# Build xlogin-git
RUN	pacman -Sy --noconfirm xorg-server && \
	mkdir -p $BUILD_DIR $OUT_DIR && \
	chmod 777 -R $BUILD_DIR $OUT_DIR && \
	(cd $BUILD_DIR;sudo -u nobody HOME=$BUILD_DIR yaourt -S --noconfirm --export $OUT_DIR xlogin-git) && \
	pacman -Rcns --noconfirm xorg-server && \
	cp -r $OUT_DIR/*.pkg.tar.xz $PACKAGES_DIR/ && \
	rm -rf $BUILD_DIR $OUT_DIR /var/cache/pacman/*


FROM archminer_builder as archminer_custom_kernel_builder

# Replace binutils
ADD ./binutils-git /tmp/build/binutils-git
RUN pacman -Sy && \
	chmod 777 -R $BUILD_DIR && \
	(cd $BUILD_DIR/binutils-git;sudo -u nobody HOME=$BUILD_DIR PKGDEST=$BUILD_DIR makepkg -s --noconfirm) && \
	pacman -Rdd --noconfirm binutils && \
	pacman -U --noconfirm $BUILD_DIR/*.pkg.tar.xz && \
	cp -r $BUILD_DIR/*.pkg.tar.xz $PACKAGES_DIR/ && \
	rm -rf $BUILD_DIR /var/cache/pacman/*

# Install gcc7 to build old kernel
RUN mkdir -p $BUILD_DIR && \
	chmod 777 -R $BUILD_DIR && \
	(cd $BUILD_DIR;sudo -u nobody HOME=$BUILD_DIR yaourt -Sy --noconfirm gcc7) && \
	rm -rf $BUILD_DIR /var/cache/pacman/*

# Replace gcc
RUN pacman -R gcc --noconfirm && \
	ln -s $(which cc-7) /usr/local/bin/cc && \
	ln -s $(which gcc-7) /usr/local/bin/gcc && \
	ln -s $(which gcc-ar-7) /usr/local/bin/gcc-ar && \
	ln -s $(which gcc-ranlib-7) /usr/local/bin/gcc-ranlib && \
	rm -rf /var/cache/pacman/*

# Build custom kernel 4.14.15-1 80d6f250c03d7999a35bf4213911
# linux 4.15.1-4 93f72cf795641e517c68dea2f299778521f5fa42
RUN pacman -Sy asp gnupg --noconfirm && \
	mkdir -p $BUILD_DIR $OUT_DIR && \
	chmod 777 -R $BUILD_DIR $OUT_DIR && \
	cd $BUILD_DIR && \
	asp checkout linux && \
	(cd ./linux;git checkout 80d6f250c03d7999a35bf4213911) && \
	sudo -u nobody HOME=$BUILD_DIR gpg --keyserver hkp://keyserver.ubuntu.com --keyserver-options self-sigs-only --recv-keys ABAF11C65A2970B130ABE3C479BE3E4300411886 && \
	sudo -u nobody HOME=$BUILD_DIR gpg --keyserver hkp://keyserver.ubuntu.com --keyserver-options self-sigs-only --recv-keys 647F28654894E3BD457199BE38DBBDC86092693E && \
	sudo -u nobody HOME=$BUILD_DIR gpg --keyserver hkp://keyserver.ubuntu.com --keyserver-options self-sigs-only --recv-keys 8218F88849AAC522E94CF470A5E9288C4FA415FA && \
	chmod 777 -R ./linux && \
	(cd ./linux/trunk;sudo -u nobody HOME=$BUILD_DIR PKGDEST=$OUT_DIR makepkg -s --noconfirm) && \
	pacman -Rcns --noconfirm asp && \
	cp -r $OUT_DIR/*.pkg.tar.xz $PACKAGES_DIR/ && \
	rm -rf $BUILD_DIR $OUT_DIR /var/cache/pacman/*


