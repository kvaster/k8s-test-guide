#!/bin/sh

set -e

img=$1

tmp=tmp-pxe
dst=gentoo-pxe.zip

rm -rf $tmp $dst $dst.sha512
mkdir tmp-pxe

# structure
mkdir -p $tmp/tftp/boot

# iso
mkdir -p $tmp/iso
mount -o loop $img $tmp/iso

# kernel
cp $tmp/iso/boot/gentoo $tmp/tftp/boot/

# initrd
mkdir -p $tmp/initrd
xz -dc $tmp/iso/boot/gentoo.igz | cpio -id -D $tmp/initrd

patch_path=$(readlink -f $(dirname $0)/initrd.patch)
patch -d $tmp/initrd -p1 -i $patch_path
cp $tmp/iso/image.squashfs $tmp/initrd

pushd $tmp/initrd
find . -print | cpio -o -H newc | gzip -9 -c - > ../tftp/boot/gentoo.igz
popd

# umount iso
umount $tmp/iso

# loaders
cp /usr/share/syslinux/{pxelinux.0,ldlinux.c32} $tmp/tftp/

# create zip
7z a gentoo-pxe.zip $tmp/tftp/.
sha512sum $dst > $dst.sha512

# clean-up
rm -rf $tmp
