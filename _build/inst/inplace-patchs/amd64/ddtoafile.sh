ddtoafile(){

  tmpMNT="$topdir/mnt"
  tmpDEV=$(mount | grep "$tmpMNT" | awk '{print $1}')

  sleep 2s && echo -en "\n - clearing the scaffold image file: ..."

  umount -f -l "$tmpMNT"_p2 "$tmpMNT"_p3 >/dev/null 2>&1
  if mountpoint -q "$tmpMNT"_p2;then echo "$tmpMNT"_p2 still mounted && exit 1;fi
  if mountpoint -q "$tmpMNT"_p3;then echo "$tmpMNT"_p3 still mounted && exit 1;fi
  losetup -j "$topdir/imgscafford"|while read line;do sudo losetup -d `echo $line|awk '{print $1}'|sed 's/://'`;done
  losetup -j "$topdir/imgscafford (deleted)"|while read line;do sudo losetup -d `echo $line|awk '{print $1}'|sed 's/://'`;done
  rm -rf $topdir/imgscafford "$tmpMNT"_p2 "$tmpMNT"_p3

  sleep 2s && echo -en "\n - preparing the scaffold image file: ..."

  [ -z "$tmpDEV" ] && {

    dd if=/dev/zero of=$topdir/imgscafford bs=512 seek=`expr 2048 \* 1024 \* $custIMGSIZE` count=0 >/dev/null 2>&1
    tmpDEV=`losetup -fP --show $topdir/imgscafford | awk '{print $1}'`
    sleep 2s && echo -en "[ \033[32m dev:$tmpDEV \033[0m ]"
    
    [ -n "$tmpDEV" ] && {

      # we must guarantee the 200m as fat32(not fat16) tagged and formatted both in mbr or gpt,or the linuxlive wont recongize it
      parted -s "$tmpDEV" mklabel gpt >/dev/null 2>&1 && \
      parted -s "$tmpDEV" \
      mkpart non-fs 2048s `echo $(expr 2048 \* 2 - 1)s` \
      mkpart rom    `echo $(expr 2048 \* 2)s` `echo $(expr 2048 \* 2 + 2048 \* 100 - 1)s` \
      mkpart rom2   `echo $(expr 2048 \* 2 + 2048 \* 100)s` `echo $(expr 2048 \* 2 + 2048 \* 200 - 1)s` \
      mkpart sys    `echo $(expr 2048 \* 2 + 2048 \* 200)s` `echo $(expr 2048 \* 2 + 2048 \* 200 + 2048 \* 1024 \* 1 - 1)s` \
      mkpart data   `echo $(expr 2048 \* 2 + 2048 \* 200 + 2048 \* 1024 \* 1)s` 95% \
      mkpart swap   95% 100% >/dev/null 2>&1 && \
      parted -s "$tmpDEV" set 1 bios_grub on set 1 hidden on set 3 boot on set 3 esp on >/dev/null 2>&1 && \
      mkfs.ext2 "$tmpDEV"p2 -L "ROM" >/dev/null 2>&1 && \
      mkfs.fat -F16 "$tmpDEV"p3 -n "ROM2" >/dev/null 2>&1 && \
      mkfs.ext4 "$tmpDEV"p4 -L "SYS" >/dev/null 2>&1 && \
      mkfs.ext4 "$tmpDEV"p5 -L "DATA" >/dev/null 2>&1 && \
      mkswap "$tmpDEV"p6 -L "SWAP" >/dev/null 2>&1
    }

    [ ! -d "$tmpMNT" ] && \
      mkdir -p "$tmpMNT"_p2 "$tmpMNT"_p3 "$tmpMNT"_p4 "$tmpMNT"_p5 && \
      mount "$tmpDEV"p2 "$tmpMNT"_p2 && mount "$tmpDEV"p3 "$tmpMNT"_p3 && mount "$tmpDEV"p4 "$tmpMNT"_p4 && mount "$tmpDEV"p5 "$tmpMNT"_p5
      sleep 2s && echo -en "[ \033[32m mnts: ""$tmpMNT"_p2" ""$tmpMNT"_p3" ""$tmpMNT"_p4" ""$tmpMNT"_p5" \033[0m ]"
  }

  sleep 2s && echo -en "\n - processing the scaffold image file: ..."

  cat $topdir/$downdir/vmlinuz >> "$tmpMNT"_p2/vmlinuz
  cat $topdir/$downdir/initrfs.img >> "$tmpMNT"_p2/initrfs.img
  cat $topdir/$downdir/x.xz|tar Jx -C "$tmpMNT"_p4

  #mv "$tmpMNT"_p4/01-core/boot/grub "$tmpMNT"_p2
  #mv "$tmpMNT"_p4/01-core/boot/EFI "$tmpMNT"_p3
  chrootdir=$topdir/$remasteringdir/onekeydevdeskd/01-core

  mkdir -p $chrootdir/boot/grub $chrootdir/boot/EFI/boot

  ar -p $topdir/$downdir/debianbase/dists/bullseye/main/binary-amd64/deb/grub-pc-bin_2.06-3~deb11u5_amd64.deb data.tar.xz |xzcat|tar -xf - -C $chrootdir/boot ./usr/lib/grub/ --strip-components=3
  ar -p $topdir/$downdir/debianbase/dists/bullseye/main/binary-amd64/deb/grub-efi-amd64-bin_2.06-3~deb11u5_amd64.deb data.tar.xz |xzcat|tar -xf - -C $chrootdir/boot ./usr/lib/grub/ --strip-components=3

  mkdir -p $chrootdir/boot/grub/fonts
  ar -p $topdir/$downdir/debianbase/dists/bullseye/main/binary-amd64/deb/grub-common_2.06-3~deb11u5_amd64.deb data.tar.xz |xzcat|tar -xf - -C $chrootdir/boot/grub/fonts ./usr/share/grub/unicode.pf2 --strip-components=4

  # some dedicated servers need by-uuid but not by-devicename,so we use the regluar one
  # and in orcarm platform, in case there is a no suitable video mode found error
  cat > $chrootdir/boot/grub/grub.cfg <<'EOF'
### BEGIN /etc/grub.d/00_header ###
if [ -s $prefix/grubenv ]; then
  set have_grubenv=true
  load_env
fi
if [ "${next_entry}" ] ; then
   set default="${next_entry}"
   set next_entry=
   save_env next_entry
   set boot_once=true
else
   set default="0"
fi

if [ x"${feature_menuentry_id}" = xy ]; then
  menuentry_id_option="--id"
else
  menuentry_id_option=""
fi

export menuentry_id_option

if [ "${prev_saved_entry}" ]; then
  set saved_entry="${prev_saved_entry}"
  save_env saved_entry
  set prev_saved_entry=
  save_env prev_saved_entry
  set boot_once=true
fi

function savedefault {
  if [ -z "${boot_once}" ]; then
    saved_entry="${chosen}"
    save_env saved_entry
  fi
}
function load_video {
  if [ x$feature_all_video_module = xy ]; then
    insmod all_video
  else
    insmod efi_gop
    insmod efi_uga
    insmod ieee1275_fb
    insmod vbe
    insmod vga
    insmod video_bochs
    insmod video_cirrus
  fi
}
## added to template 00_header
# load common disk partation and file system
function load_sas {
  insmod part_gpt
  insmod part_msdos
  insmod exfat
  insmod ext2
  insmod fat
  insmod iso9660
  insmod btrfs
  insmod lvm
  insmod dm_nv
  insmod mdraid09_be
  insmod mdraid09
  insmod mdraid1x
  insmod raid5rec
  insmod raid6rec
}
#Set superuser and password
set superusers=admin
password_pbkdf2 admin grub.pbkdf2.sha512.10000.7E4B108C243BC281A5D40E3694F70B15FB7765487E0711BAD442657AB0D1094233ABA74A75DBBA3CA49FD4A658FF59A95E4C822790D17B3C290887E8B6D02842.E23AB60D6CAF38CFC75D1C65E8A817088883AF0A6C6A3864CAD6D2DF2AB15303A0AF981B9003B67FECEF1CA2BCB2F577B1B06881067B08315813FF3129C818DC
## end added to template 00_header

if [ x$feature_default_font_path = xy ] ; then
   font=unicode
else
  load_sas
  set root=(hd0,gptBOOTPARTNO)
  if [ x$feature_platform_search_hint = xy ]; then
    search --no-floppy --fs-uuid --set=root --hint-bios=hd0,gptBOOTPARTNO --hint-efi=hd0,gptBOOTPARTNO --hint-baremetal=ahci0,gptBOOTPARTNO BOOTFSUUID
  else
    search --no-floppy --fs-uuid --set=root BOOTFSUUID
  fi
  font="/usr/share/grub/unicode.pf2"
fi

if loadfont $font ; then
  set gfxmode=auto
  load_video
  insmod gfxterm
  set locale_dir=$prefix/locale
  set lang=en_US
  insmod gettext
fi
terminal_output gfxterm
if [ "${recordfail}" = 1 ] ; then
  set timeout=30
else
  if [ x$feature_timeout_style = xy ] ; then
    set timeout_style=menu
    set timeout=5
  # Fallback normal timeout code in case the timeout_style feature is
  # unavailable.
  else
    set timeout=5
  fi
fi
### END /etc/grub.d/00_header ###

### BEGIN /etc/grub.d/05_debian_theme ###
load_sas
set root=(hd0,gptBOOTPARTNO)
if [ x$feature_platform_search_hint = xy ]; then
  search --no-floppy --fs-uuid --set=root --hint-bios=hd0,gptBOOTPARTNO --hint-efi=hd0,gptBOOTPARTNO --hint-baremetal=ahci0,gptBOOTPARTNO BOOTFSUUID
else
  search --no-floppy --fs-uuid --set=root BOOTFSUUID
fi
insmod png
if background_image /usr/share/desktop-base/futureprototype-theme/grub/grub-4x3.png; then
  set color_normal=white/black
  set color_highlight=black/white
else
  set menu_color_normal=cyan/blue
  set menu_color_highlight=white/blue
fi
### END /etc/grub.d/05_debian_theme ###

### BEGIN /etc/grub.d/10_linux ###
function gfxmode {
	set gfxpayload="${1}"
}
set linux_gfx_mode=
export linux_gfx_mode
menuentry 'start devdeskos' --unrestricted --class debian --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-simple-BOOTFSUUID' {
	load_video
	insmod gzio
	if [ x$grub_platform = xxen ]; then insmod xzio; insmod lzopio; fi
	load_sas
	set root=(hd0,gptBOOTPARTNO)
	if [ x$feature_platform_search_hint = xy ]; then
	  search --no-floppy --fs-uuid --set=root --hint-bios=hd0,gptBOOTPARTNO --hint-efi=hd0,gptBOOTPARTNO --hint-baremetal=ahci0,gptBOOTPARTNO BOOTFSUUID
	else
	  search --no-floppy --fs-uuid --set=root BOOTFSUUID
	fi
	echo	'Loading ...'
	linux	/vmlinuz root=UUID=ROOTFSUUID console=ttyS0,115200n8 console=tty0 net.ifnames=0 biosdevname=0 live=core slax.flags=perch cgroup_enable=memory cgroup_memory=1 swapaccount=1 ro quiet
	initrd	/initrfs.img
}
menuentry 'start devdeskos (gui)' --unrestricted --class debian --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-simple-BOOTFSUUID' {
	load_video
	insmod gzio
	if [ x$grub_platform = xxen ]; then insmod xzio; insmod lzopio; fi
	load_sas
	set root=(hd0,gptBOOTPARTNO)
	if [ x$feature_platform_search_hint = xy ]; then
	  search --no-floppy --fs-uuid --set=root --hint-bios=hd0,gptBOOTPARTNO --hint-efi=hd0,gptBOOTPARTNO --hint-baremetal=ahci0,gptBOOTPARTNO BOOTFSUUID
	else
	  search --no-floppy --fs-uuid --set=root BOOTFSUUID
	fi
	echo	'Loading ...'
	linux	/vmlinuz root=UUID=ROOTFSUUID console=ttyS0,115200n8 console=tty0 net.ifnames=0 biosdevname=0 live=gui slax.flags=perch cgroup_enable=memory cgroup_memory=1 swapaccount=1 ro quiet
	initrd	/initrfs.img
}
submenu 'start devdeskos recovery' --users admin $menuentry_id_option 'gnulinux-advanced-BOOTFSUUID' {
	echo "dangerous area,please be clear what you are doing before 100s auto enter,or press esc to quick confirm..."
	echo
	echo
	if sleep --interruptible 100 ; then
	  set timeout=0
	fi
	menuentry 'reinstall devdeskos' --class debian --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-5.10.0-22-amd64-advanced-BOOTFSUUID' {
		load_video
		insmod gzio
		if [ x$grub_platform = xxen ]; then insmod xzio; insmod lzopio; fi
		load_sas
		set root=(hd0,gptBOOTPARTNO)
		if [ x$feature_platform_search_hint = xy ]; then
		  search --no-floppy --fs-uuid --set=root --hint-bios=hd0,gptBOOTPARTNO --hint-efi=hd0,gptBOOTPARTNO --hint-baremetal=ahci0,gptBOOTPARTNO  BOOTFSUUID
		else
		  search --no-floppy --fs-uuid --set=root BOOTFSUUID
		fi
		echo	'Loading ...'
		linux	/vmlinuz root=UUID=ROOTFSUUID console=ttyS0,115200n8 console=tty0 net.ifnames=0 biosdevname=0 debian-installer/framebuffer=false DEBIAN_FRONTEND=text auto=true hostname=debian domain= -- quiet
		initrd	/initrfs.img
	}
	menuentry 'erase data volume' --class debian --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-5.10.0-22-amd64-recovery-BOOTFSUUID' {
		load_video
		insmod gzio
		if [ x$grub_platform = xxen ]; then insmod xzio; insmod lzopio; fi
		load_sas
		set root=(hd0,gptBOOTPARTNO)
		if [ x$feature_platform_search_hint = xy ]; then
		  search --no-floppy --fs-uuid --set=root --hint-bios=hd0,gptBOOTPARTNO --hint-efi=hd0,gptBOOTPARTNO --hint-baremetal=ahci0,gptBOOTPARTNO BOOTFSUUID
		else
		  search --no-floppy --fs-uuid --set=root BOOTFSUUID
		fi
		echo	'Loading ...'
		linux	/vmlinuz root=UUID=ROOTFSUUID ro single
		initrd	/initrfs.img
	}
}
### END /etc/grub.d/10_linux ###
EOF

  cat > $chrootdir/boot/EFI/boot/grub.cfg <<'EOF'
# redirect only the grub files to let two set of grub shedmas coexists
search --label "ROM" --set root
configfile ($root)/grub/grub.cfg
EOF

  mkdir -p "$tmpMNT"_p4/onekeydevdesk
  mv "$tmpMNT"_p4/01-core "$tmpMNT"_p4/02-gui "$tmpMNT"_p4/onekeydevdesk

  [[ $tmpHOSTARCH == '0' ]] && grub-mkimage -C xz -O i386-pc -o "$tmpMNT"_p2/grub/i386-pc/core.img -p "(hd0,gpt2)/grub" -d "$tmpMNT"_p2/grub/i386-pc biosdisk part_msdos part_gpt exfat ext2 fat iso9660 btrfs lvm dm_nv mdraid09_be mdraid09 mdraid1x raid5rec raid6rec
  [[ $tmpHOSTARCH == '0' ]] && "$tmpMNT"_p2/grub/i386-pc/grub-bios-setup -d "$tmpMNT"_p2/grub/i386-pc -b boot.img -c core.img "$tmpDEV"
  [[ $tmpHOSTARCH == '0' ]] && grub-mkimage -C xz -O x86_64-efi -o "$tmpMNT"_p3/EFI/boot/bootx64.efi -p "(hd0,gpt2)/grub" -d "$tmpMNT"_p2/grub/x86_64-efi part_msdos part_gpt exfat ext2 fat iso9660 btrfs lvm dm_nv mdraid09_be mdraid09 mdraid1x raid5rec raid6rec || grub-mkimage -C xz -O arm64-efi -o "$tmpMNT"_p3/EFI/boot/bootaa64.efi -p "(hd0,gpt2)/grub" -d "$tmpMNT"_p2/grub/arm64-efi part_msdos part_gpt exfat ext2 fat iso9660 btrfs lvm dm_nv mdraid09_be mdraid09 mdraid1x raid5rec raid6rec

  bootfsuuid=`blkid -s UUID -o value "$tmpDEV"p2`
  rootfsuuid=`blkid -s UUID -o value "$tmpDEV"p5`
  # dont -e s/ROOTFSUUID/$rootfsuuid/g or the grubmenu wont show
  sed -e s/BOOTPARTNO/2/g -e s/BOOTFSUUID/$bootfsuuid/g -e s/ROOTFSUUID/$rootfsuuid/g -i "$tmpMNT"_p2/grub/grub.cfg
  #sed -e s/BOOTFSUUID/$bootfsuuid/g -e s/UEFIFSUUID/$uefifsuuid/g -e s/SWAPFSUUID/$swapfsuuid/g -e s/ROOTFSUUID/$rootfsuuid/g -i $remasteringdir/fstab
  mkdir -p "$tmpMNT"_p2/efi "$tmpMNT"_p5/sys "$tmpMNT"_p5/dockerd "$tmpMNT"_p5/onekeydevdeskd "$tmpMNT"_p5/onekeydevdeskd/changes1 "$tmpMNT"_p5/onekeydevdeskd/changes2 "$tmpMNT"_p5/onekeydevdeskd/updates
  mkdir -p "$tmpMNT"_p4/onekeydevdesk/01-core/var/lib/lxcfs "$tmpMNT"_p4/onekeydevdesk/01-core/var/lib/dhcp "$tmpMNT"_p4/onekeydevdesk/01-core/var/lib/rrdcached/db

  > $topdir/start.txt
  tee -a $topdir/start.txt > /dev/null <<EOF
#for linux
# -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd -drive if=pflash,format=raw,file=/usr/share/OVMF/OVMF_VARS.fd
qemu-system-x86_64 -accel kvm -accel tcg -machine q35 -smp 2 -m 1G \\
-vga std -usbdevice tablet -usbdevice keyboard -drive "file=./imgscafford,format=raw" -net nic,model=virtio-net-pci -net user \\
-boot order=c,menu=on

#for osx
# -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd -drive if=pflash,format=raw,file=/usr/share/OVMF/OVMF_VARS.fd
qemu-system-x86_64 -accel hvf -accel tcg -machine q35 -smp 2 -m 1G \\
-vga std -usbdevice tablet -usbdevice keyboard -drive "file=./imgscafford,format=raw" -net nic,model=virtio-net-pci -net vmnet-shared \\
-boot order=c,menu=on

#for win
# -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd -drive if=pflash,format=raw,file=/usr/share/OVMF/OVMF_VARS.fd
"C:\Program Files\qemu\qemu-system-x86_64" -accel whpx -accel tcg -machine q35 -smp 2 -m 1G ^
-vga std -usbdevice tablet -usbdevice keyboard -drive "file=./imgscafford,format=raw" -net nic,model=virtio-net-pci -net user ^
-boot order=c,menu=on
EOF

}
