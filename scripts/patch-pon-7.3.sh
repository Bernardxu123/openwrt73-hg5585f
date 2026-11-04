#!/bin/sh
# Linux 7.3 moved hex2bin() declarations from <linux/kernel.h> to
# <linux/hex.h>.  pbs05's airoha-xpon still relies on the old transitive
# include, which only shows up when built against 7.3.
set -e

f=feeds/pon_drivers/airoha-xpon/src/airoha-xpon-identity.c
[ -f "$f" ] || {
	echo "patch-pon-7.3: $f not found (feeds not installed?)" >&2
	exit 1
}

if ! grep -q '#include <linux/hex.h>' "$f"; then
	sed -i '/#include <linux\/string.h>/a #include <linux/hex.h>' "$f"
fi

grep -q '#include <linux/hex.h>' "$f"
