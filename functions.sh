#!/bin/bash

# Set hostname from DHCP
fix_hostname() {
	NEWHOSTNAME=`hostname|sed -e 's/\..*//'`
	NEWDOMAIN=`hostname|sed -e 's/[^.]*\.//'`
	echo $NEWHOSTNAME > /etc/hostname
}

# Set system time from NTP and hwclock
configure_time() {
	echo "Setting time..."
	hwclock -s
	ntpdate ntp
	hwclock -w
}

# Creates EFI partition
create_efi() {
	mkfs.fat -F32 $EFI_DEVICE
	mount_efi
	mkdir -p /mnt/efi/EFI/
	umount_efi
}

# Sets default block devices if they are not set
set_block_devices() {
	if [ -z $DISK ]; then
		DISK=/dev/sda
	fi

	if [ $UEFI = true ]; then
		if [ -z $DEVICE ]; then
			DEVICE=${DISK}2
		fi

		if [ -z $EFI_DEVICE ]; then
			EFI_DEVICE=${DISK}1
		fi
	else
		if [ -z $DEVICE ]; then
			DEVICE=${DISK}1
		fi
	fi
}

mount_efi() {
	mount $EFI_DEVICE /mnt/efi || { echo "ERROR: mount $DEVICE failed"; exit 5; }
	cat /proc/mounts > /etc/mtab
}

umount_efi() {
	umount /mnt/efi
	cat /proc/mounts > /etc/mtab
}

mount_win() {
	mount -o permissions $DEVICE /mnt/hd || { echo "ERROR: mount $DEVICE failed"; exit 5; }
	cat /proc/mounts > /etc/mtab
}

umount_win() {
	umount /mnt/hd
	cat /proc/mounts > /etc/mtab
}

mount_lin() {

	mount $DEVICE /mnt/hd
	mount -t proc proc /mnt/hd/proc
	mount -o bind /dev /mnt/hd/dev/
	mount -o bind /sys /mnt/hd/sys/
}

umount_lin() {
	umount /mnt/hd/sys
	umount /mnt/hd/proc
	umount /mnt/hd/dev
	umount /mnt/hd
}

win_reg_set_utc_time() {
	mount_win

	echo -e "cd ControlSet001\\Control\\TimeZoneInformation\nnv 4 RealTimeIsUniversal\ned RealTimeIsUniversal\n1\nq\ny" | chntpw -e /mnt/hd/Windows/System32/config/SYSTEM

	umount_win
}

fix_grub2() {
	mount_lin
	chroot /mnt/hd /usr/sbin/update-grub
	if [ $UEFI = true ]; then
		mount $EFI_DEVICE /mnt/hd/boot/efi
		chroot /mnt/hd /usr/sbin/grub-install --target=x86_64-efi --force $DISK
		umount /mnt/hd/boot/efi
	else
		chroot /mnt/hd /usr/sbin/grub-install --force $DISK
	fi
	umount_lin
}

# Restore partition table from ptable, ptable.sfdisk or ptable.sgdisk
restore_ptable() {
	ROOTDEVICE=$(echo $DISK|sed -e 's/^\([a-z\/]*\).*/\1/')

	cd $IMAGEPATH/komputery/$BASECOMP
	echo `pwd`
	if [ -e ptable ]; then
		echo "Taking as ptable: ptable"
		dd if=ptable of=$ROOTDEVICE
	elif [ -e ptable.sfdisk ]; then
		echo "Taking as ptable: ptable.sfdisk"
		sfdisk $ROOTDEVICE < ptable.sfdisk
	elif [ -e ptable.sgdisk ]; then
		echo "Taking as ptable: ptable.sgdisk"
		sgdisk --zap-all $ROOTDEVICE
		sgdisk --load-backup=ptable.sgdisk $ROOTDEVICE
		sgdisk --randomize-guids $ROOTDEVICE
	elif [ -e $IMAGEPATH/res/ptable.sfdisk ]; then
		echo "Taking as ptable: ptable.sfdisk"
		sfdisk $ROOTDEVICE < $IMAGEPATH/res/ptable.sfdisk
	else
		echo "No valid ptable found!"
		exit 2
	fi
	cd $IMAGEPATH
	sync
	blockdev --rereadpt $ROOTDEVICE
}

recreate_windows_efi() {
	mount_efi
	mount_win

	mkdir -p /mnt/efi/EFI/Microsoft/Boot/
	cp -r /mnt/hd/Windows/Boot/EFI/. /mnt/efi/EFI/Microsoft/Boot/
	if [ -f $IMAGEPATH/komputery/$BASECOMP/BCD ]; then
		BCD_FILE=$IMAGEPATH/komputery/$BASECOMP/BCD
	else
		BCD_FILE=$IMAGEPATH/res/BCD
	fi
	cp $BCD_FILE /mnt/efi/EFI/Microsoft/Boot/BCD

	umount_efi
	umount_win
}

install_debian() {
	if [ $UEFI = true ]; then
		GRUB_VARIANT=grub-efi
	else
		GRUB_VARIANT=grub-pc
	fi

	mkfs.ext4 -c -FF $DEVICE
	mount $DEVICE /mnt/hd
	mmdebstrap --include=linux-image-amd64,$GRUB_VARIANT,xserver-xorg-video-all,gnome,gnome-shell-extension-dash-to-panel,libreoffice-gtk3,bash-completion,vim,nano,htop,locales,firefox-esr-l10n-pl,libreoffice-l10n-pl,$INSTALL_APPS --arch amd64 $DEBIAN_VERSION /mnt/hd http://ftp.pl.debian.org/debian/

	echo -e "$DEVICE\t/\text4\terrors=remount-ro\t0\t1" > /mnt/hd/etc/fstab
	if [ $UEFI = true ]; then
		mkdir /mnt/hd/boot/efi/
		echo -e "$EFI_DEVICE\t/boot/efi\tvfat\tdefaults\t0\t1" >> /mnt/hd/etc/fstab
	fi

	echo GRUB_DISABLE_RECOVERY=\"true\" >> /mnt/hd/etc/default/grub
	echo sleep-inactive-ac-type=\'blank\' >> /mnt/hd/etc/gdm3/greeter.dconf-defaults
	echo -e "[org.gnome.desktop.wm.preferences]\nbutton-layout='appmenu:minimize,maximize,close'\nnum-workspaces=1\n\n[org.gnome.desktop.interface]\nenable-hot-corners=false\n\n[org.gnome.shell]\nfavorite-apps=['firefox-esr.desktop', 'libreoffice-writer.desktop', 'org.gnome.Nautilus.desktop']\nenabled-extensions=['drive-menu@gnome-shell-extensions.gcampax.github.com', 'places-menu@gnome-shell-extensions.gcampax.github.com', 'apps-menu@gnome-shell-extensions.gcampax.github.com', 'dash-to-panel@jderose9.github.com']\n\n[org.gnome.shell.extensions.dash-to-panel]\npanel-size=32\nshow-show-apps-button=false\n\n[org.gnome.login-screen]\ndisable-user-list=true\n\n[org.gnome.settings-daemon.plugins.power]\nsleep-inactive-ac-type='nothing'" > /mnt/hd/usr/share/glib-2.0/schemas/00_xivlo.gschema.override
	chroot /mnt/hd glib-compile-schemas /usr/share/glib-2.0/schemas/
	echo Europe/Warsaw > /mnt/hd/etc/timezone
	ln -sf /usr/share/zoneinfo/Europe/Warsaw /mnt/hd/etc/localtime
	echo pl_PL\.UTF-8\ UTF-8 >> /mnt/hd/etc/locale.gen
	chroot /mnt/hd locale-gen
	echo LANG=\"pl_PL.utf8\" > /mnt/hd/etc/default/locale
	echo KEYMAP=pl2 > /mnt/hd/etc/vconsole.conf
	sed -i -e 's/XKBLAYOUT=.*/XKBLAYOUT=pl/' /mnt/hd/etc/default/keyboard
	umount /mnt/hd

	fix_grub2
}

install_windows() {
	mkfs.ntfs --fast --label Windows $DEVICE
	wimapply obrazy/windows_images/Win_Pro_10_2004_64BIT_Polish.wim 5 $DEVICE
	recreate_windows_efi
}

uninstall_windows_apps() {
	UNINSTALL_APPS="Microsoft.SkypeApp Microsoft.Xbox.TCUI Microsoft.XboxApp Microsoft.XboxGameOverlay Microsoft.XboxGamingOverlay Microsoft.XboxIdentityProvider Microsoft.XboxSpeechToTextOverlay Microsoft.MicrosoftOfficeHub Microsoft.OneConnect Microsoft.Messaging"

	for I in $UNINSTALL_APPS; do
		rm -r /mnt/hd/Program\ Files/WindowsApps/${I}_*
	done
}
