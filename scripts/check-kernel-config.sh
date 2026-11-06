#!/bin/sh
# Gate on the generated 7.3 kernel .config before the long build starts.
#
# It fails early when a symbol needed by honk (CO-RE/eBPF), nft-fullcone
# (NAT1) or the software-offload A/B is missing, which is much cheaper than
# discovering it after the image build.
#
# Tristate netfilter symbols are accepted as either y or m: OpenWrt normally
# builds them as kmods (kmod-nft-core, kmod-nf-flow, kmod-nft-offload).
set -e

cfg="$(find build_dir -path '*/linux-7.3.1/.config' -print -quit 2>/dev/null || true)"
[ -n "$cfg" ] || {
	echo "check-kernel-config: kernel .config not found" >&2
	exit 1
}

echo "check-kernel-config: $cfg"
grep -E '^(CONFIG_DEBUG_INFO|CONFIG_CGROUPS|CONFIG_CGROUP_BPF|CONFIG_KPROBES|CONFIG_TRACEPOINTS|CONFIG_NETKIT|CONFIG_FRAME_WARN|CONFIG_FUNCTION_TRACER|CONFIG_QUEUED_SPINLOCKS_TRACE_CONTENDED_RELEASE|CONFIG_NF_TABLES|CONFIG_NF_CONNTRACK_EVENTS|CONFIG_NF_CONNTRACK_CHAIN_EVENTS|CONFIG_NF_FLOW_TABLE|CONFIG_NFT_FLOW_OFFLOAD)' "$cfg" || true

fail=0

# bool symbols: must be built in
for sym in \
	'CONFIG_DEBUG_INFO' \
	'CONFIG_DEBUG_INFO_BTF' \
	'CONFIG_CGROUPS' \
	'CONFIG_KPROBES' \
	'CONFIG_TRACEPOINTS' \
	'CONFIG_NETKIT' \
	'CONFIG_CGROUP_BPF' \
	'CONFIG_NF_CONNTRACK_EVENTS' \
	'CONFIG_NF_CONNTRACK_CHAIN_EVENTS'
do
	grep -qx "${sym}=y" "$cfg" || { echo "MISSING: ${sym}=y" >&2; fail=1; }
done

# tristate symbols: y or m both satisfy the feature. NF_TABLES is not checked
# here: OpenWrt merges kmod KCONFIG fragments later in the build, so it is
# absent from the config at this point even though kmod-nft-core provides it.
for sym in \
	'CONFIG_NF_FLOW_TABLE' \
	'CONFIG_NFT_FLOW_OFFLOAD'
do
	grep -Eq "^${sym}=(y|m)$" "$cfg" || { echo "MISSING: ${sym}=y|m" >&2; fail=1; }
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
