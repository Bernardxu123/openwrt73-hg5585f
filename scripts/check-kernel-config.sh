#!/bin/sh
# Gate on the generated 7.3 kernel .config before the long build starts.
#
# It fails early when a symbol needed by honk (CO-RE/eBPF), nft-fullcone
# (NAT1) or the software-offload A/B is missing, which is much cheaper than
# discovering it after the image build.
set -e

cfg="$(find build_dir -path '*/linux-7.3.1/.config' -print -quit 2>/dev/null || true)"
[ -n "$cfg" ] || {
	echo "check-kernel-config: kernel .config not found" >&2
	exit 1
}

echo "check-kernel-config: $cfg"
grep -E '^(CONFIG_DEBUG_INFO|CONFIG_CGROUPS|CONFIG_CGROUP_BPF|CONFIG_KPROBES|CONFIG_TRACEPOINTS|CONFIG_NETKIT|CONFIG_FRAME_WARN|CONFIG_FUNCTION_TRACER|CONFIG_QUEUED_SPINLOCKS_TRACE_CONTENDED_RELEASE|CONFIG_NF_CONNTRACK_EVENTS|CONFIG_NF_CONNTRACK_CHAIN_EVENTS|CONFIG_NF_FLOW_TABLE|CONFIG_NFT_FLOW_OFFLOAD)' "$cfg" || true

fail=0
for sym in \
	'CONFIG_DEBUG_INFO=y' \
	'CONFIG_DEBUG_INFO_BTF=y' \
	'CONFIG_CGROUPS=y' \
	'CONFIG_KPROBES=y' \
	'CONFIG_TRACEPOINTS=y' \
	'CONFIG_NETKIT=y' \
	'CONFIG_CGROUP_BPF=y' \
	'CONFIG_FRAME_WARN=2048' \
	'CONFIG_NF_TABLES=y' \
	'CONFIG_NF_CONNTRACK_EVENTS=y' \
	'CONFIG_NF_CONNTRACK_CHAIN_EVENTS=y' \
	'CONFIG_NF_FLOW_TABLE=y' \
	'CONFIG_NFT_FLOW_OFFLOAD=y'
do
	grep -qx "$sym" "$cfg" || { echo "MISSING: $sym" >&2; fail=1; }
done
for sym in \
	'# CONFIG_FUNCTION_TRACER is not set' \
	'# CONFIG_QUEUED_SPINLOCKS_TRACE_CONTENDED_RELEASE is not set'
do
	grep -qx "$sym" "$cfg" || { echo "MISSING: $sym" >&2; fail=1; }
done

[ "$fail" = 0 ] || exit 1
echo "check-kernel-config: OK"
