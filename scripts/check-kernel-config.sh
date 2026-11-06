#!/bin/sh
# Gate on the generated 7.3 kernel .config before the long build starts.
#
# It only asserts symbols that OpenWrt already merges before this point
# (generic + subtarget + .config CONFIG_KERNEL_*): the honk/eBPF set.
#
# Netfilter symbols used by nft-fullcone (NF_CONNTRACK_EVENTS,
# NF_CONNTRACK_CHAIN_EVENTS) and by the flowtable A/B (NF_FLOW_TABLE,
# NFT_FLOW_OFFLOAD) are deliberately NOT asserted here: OpenWrt merges the
# kmod KCONFIG fragments later in the build, so they are still absent from
# the generated .config at this point even though kmod-nft-fullcone,
# kmod-nf-flow and kmod-nft-offload provide them. They are verified at
# runtime instead (lsmod + nft ruleset).
set -e

cfg="$(find build_dir -path '*/linux-7.3.1/.config' -print -quit 2>/dev/null || true)"
[ -n "$cfg" ] || {
	echo "check-kernel-config: kernel .config not found" >&2
	exit 1
}

echo "check-kernel-config: $cfg"
grep -E '^(CONFIG_DEBUG_INFO|CONFIG_CGROUPS|CONFIG_CGROUP_BPF|CONFIG_KPROBES|CONFIG_TRACEPOINTS|CONFIG_NETKIT|CONFIG_FRAME_WARN|CONFIG_FUNCTION_TRACER|CONFIG_QUEUED_SPINLOCKS_TRACE_CONTENDED_RELEASE)' "$cfg" || true
echo '--- netfilter (informational only, kmod fragments merge later) ---'
grep -E '^(CONFIG_NF_TABLES|CONFIG_NF_CONNTRACK_EVENTS|CONFIG_NF_CONNTRACK_CHAIN_EVENTS|CONFIG_NF_FLOW_TABLE|CONFIG_NFT_FLOW_OFFLOAD)' "$cfg" || echo '(absent at this stage, expected)'

fail=0
for sym in \
	'CONFIG_DEBUG_INFO' \
	'CONFIG_DEBUG_INFO_BTF' \
	'CONFIG_CGROUPS' \
	'CONFIG_KPROBES' \
	'CONFIG_TRACEPOINTS' \
	'CONFIG_NETKIT' \
	'CONFIG_CGROUP_BPF'
do
	grep -qx "${sym}=y" "$cfg" || { echo "MISSING: ${sym}=y" >&2; fail=1; }
done

grep -qx 'CONFIG_FRAME_WARN=2048' "$cfg" || { echo 'MISSING: CONFIG_FRAME_WARN=2048' >&2; fail=1; }
for sym in \
	'# CONFIG_FUNCTION_TRACER is not set' \
	'# CONFIG_QUEUED_SPINLOCKS_TRACE_CONTENDED_RELEASE is not set'
do
	grep -qx "$sym" "$cfg" || { echo "MISSING: $sym" >&2; fail=1; }
done

[ "$fail" = 0 ] || exit 1
echo "check-kernel-config: OK"
