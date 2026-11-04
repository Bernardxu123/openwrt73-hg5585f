#!/bin/sh
# Post-build assertions for the HG5585F 7.3.1 image.
# Run from the OpenWrt top directory after `make`.
set -e

fail() { echo "ASSERT FAIL: $*" >&2; exit 1; }

# 1) Kernel version pinned to 7.3.1 in the build system
grep -q '^LINUX_VERSION-7\.3 = \.1$' target/linux/generic/kernel-7.3 \
	|| fail "target/linux/generic/kernel-7.3 is not 7.3.1"

# 2) Built kernel is 7.3.1 and has the pNAND drivers enabled
uts=$(find build_dir -path '*/linux-7.3/include/generated/utsrelease.h' 2>/dev/null | head -n1)
[ -n "$uts" ] || fail "no linux-7.3 utsrelease.h (kernel not built?)"
grep -q '7\.3\.1' "$uts" || fail "built kernel is not 7.3.1: $uts"

kcfg=$(find build_dir -path '*/linux-7.3/.config' 2>/dev/null | head -n1)
[ -n "$kcfg" ] || fail "no linux-7.3 .config"
for sym in CONFIG_MTD_NAND_MTK CONFIG_MTD_NAND_ECC_MEDIATEK CONFIG_MTD_UBI_BLOCK \
	   CONFIG_MTD_UBI_NVMEM CONFIG_UIMAGE_FIT_BLK CONFIG_PCS_AIROHA \
	   CONFIG_NET_AIROHA CONFIG_MTD_ROOTFS_ROOT_DEV; do
	grep -q "^${sym}=y" "$kcfg" || fail "${sym}=y missing from kernel config"
done

# 3) Image exists and is a FIT
img=$(ls bin/targets/airoha/an7581/*-cu-squashfs-sysupgrade.itb 2>/dev/null | head -n1)
[ -n "$img" ] || fail "no CU sysupgrade.itb produced"
recovery=$(ls bin/targets/airoha/an7581/*-cu-initramfs-recovery.itb 2>/dev/null | head -n1)
[ -n "$recovery" ] || fail "no CU recovery.itb produced (RAM-boot path unavailable)"
head -c 4 "$img" | od -An -tx1 | grep -q 'd0 0d fe ed' || fail "image is not a FIT"

# 4) No fixed root password hash baked into the image (iStoreOS 97-default-settings anti-pattern)
#    OpenWrt default is an empty root hash; any '$' hash means a shared password.
for sh in $(find bin/targets -path '*/root-*/etc/shadow' 2>/dev/null); do
	if awk -F: '$1=="root" && $2 ~ /^\$/ {found=1} END{exit !found}' "$sh"; then
		fail "fixed root password hash in $sh"
	fi
done

echo "assert-image: OK ($img, $recovery)"
