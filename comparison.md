# qualcommbe 7.3 port comparison

Comparison of this tree's qualcommbe 7.3 port against
[hurrian/openwrt-w1700k, branch `qualcommbe-7.3`](https://github.com/hurrian/openwrt-w1700k/tree/qualcommbe-7.3).

## Context

Our tree: full 4-commit series (`ae2f152131`…`c607d01627`), HEAD
`qualcommbe 7.3 (4/4): fix configuration`. Theirs: a single cherry-picked
mega-commit `3567bad` "qualcommbe: add support for kernel 7.3" dated
Oct 18 2026 (7.3 release day, cherry-picked from `7f2b01ab`), "Tested working
on the Spectrum SBE1V1K". Both: `KERNEL_PATCHVER:=6.18` +
`KERNEL_TESTING_PATCHVER:=7.3` (Makefile:11-12, byte-identical), 69 vs 68
patches, no `files/` on either side, `dts/`, `image/`, `ipq95xx/base-files`,
`target.mk` all identical, and identical `target/linux/generic/patches-7.3`.

## Similarities (verified)

- **66 of 68 patches byte-identical**, same numbering and series positions.
  The only file-set difference: we add one patch (`0450`).
- The 3 non-identical patches are the same content: `0325` (MAINTAINERS
  maintainer entry — differs only in `@@` offset), `0403` (pwm period fix —
  code identical, **one comment line reworded**).
- Same config skeleton: both keep `CONFIG_ARM_QCOM_CPUFREQ_NVMEM=y`
  (ours config-7.3:57, theirs :50) and
  `# CONFIG_ARM_QCOM_CPUFREQ_HW is not set`.
- Shared generic 7.3 base (identical patches-7.3).

## Differences, with verdicts

### 1. The CPU OPP-table removal (ours-only `0450`) — the headline

We remove the ipq9574 CPU OPP table and `operating-points-v2` refs: on 7.3
final `ARM_QCOM_CPUFREQ_NVMEM` now probes (deferred forever on 6.18) and
cpufreq-dt drops the A73 cluster from the bootloader's gpll0 800 MHz to the
lowest OPP (a53pll 936 MHz), wedging the SoC — boot-verified on Askey SBE1V1K
(uncategorized exceptions in scheduler/timer softirq, secondary CPUs
unstoppable; `cpufreq.off=1` boots fine; patch commit message).

Theirs has the **same `ARM_QCOM_CPUFREQ_NVMEM=y` and no OPP removal** — their
"tested working" claim predates 7.3 final (commit dated release day,
cherry-picked, testing presumably on an -rc where the probe still deferred).

**Verdict: ours superior** — this is a required 7.3-final fix theirs lacks;
on final their build should hit the same wedge (inferred, not boot-tested
here).

### 2. Irrelevant errata: ours `=y`, theirs off

Our target `config-7.3` enables `ARM64_ERRATUM_4311569` (:30),
`HISILICON_ERRATUM_162100125` (:235), `NVIDIA_OLYMPUS_1027_ERRATUM` (:340),
`RENESAS_ERRATUM_GEN4GICITS1` (:576); their generic `config-7.3` disables all
four (verified per-file). None can fire on IPQ9574 (Cavium/Hisilicon/NVIDIA/
Renesas). Root cause: our generic `config-7.3` snapshot is older, so our
oldconfig run re-pinned the =y defaults at target level, which their generic
tree had already pruned.

**Verdict: theirs superior.**

### 3. Where the ~25 identical "not set" entries live

Ours: target `config-7.3` (AD4691, AMD_*, ARCH_BST/MICROCHIP, ARM64_MPAM,
CACHEMAINT_FOR_HOTPLUG, DEBUG_BUGVERBOSE_DETAILED, REGULATOR_*×7,
LEDS_LP5860, MFD_PF1550, the ADCs, DEVFREQ-adjacent entries…). Theirs:
generic `config-7.3` (same symbols, same values — verified identical
semantics; e.g. `DEBUG_BUGVERBOSE_DETAILED` has no default in v7.3
`lib/Kconfig.debug:221`, so both are effectively off). Effective kernel
config identical for all of them.

**Verdict: theirs superior structurally** — pruning at generic level benefits
every target; ours re-states it per target.

### 4. `POWER_SEQUENCING_QCOM_WCN` =m (ours) vs n (theirs)

Ours matches the 7.3 Kconfig default (`default m if ARCH_QCOM`, v7.3
`drivers/power/sequencing/Kconfig:18`); theirs forces it off entirely. No
user on this platform (WCN7850-class PCIe PMU).

**Verdict: tie leaning theirs** (tighter); ours harmless as an unloaded
module.

### 5. `0325` MAINTAINERS hunk offsets

Neither is zero against 7.3 final: ours applies at offset −2, theirs at −4
(verified dry-run against pristine `MAINTAINERS`, 30,222 lines; no other
patch touches MAINTAINERS). Both apply cleanly.

**Verdict: tie — both should be regenerated for zero offset; ours is
closer.**

### 6. `0403` pwm comment

One comment line reworded ("collapses to ~0% for short periods" vs "cannot
represent short ones at all"), code identical.

**Verdict: tie.**

### 7. Generic-tree drift (base, not method)

Ours' generic is newer on patches (7.3-final bump 10-23,
jool/libpfring/netatop/xtables meta-patches, eip93 fix); theirs carries extra
backports (`935-v7.3` MHI Quectel RM500Q-AE, `946-v7.4` realtek rtl8365mb,
hack `726` aquantia USXGMII) and the more complete generic config.

**Out of scope for the port itself**; flag the `946-v7.4` as the same
stale-v7.4-pattern seen on qualcommax.

### 8. Process

Ours: 4 bisectable commits with a per-step commit message; theirs: one
cherry-picked mega-commit, no readme.

**Verdict: ours superior.**

## Net

The two ports are ~97% the same tree; the only substantive difference is the
OPP-table removal — ours boot-verified against 7.3 final, theirs untested
against final — plus ours wrongly re-enabling four foreign-SoC errata and
pinning generic-level config decisions at target level. Their generic-config
work is worth adopting upward; ours' `0450` (and its failure mechanism) is
what they're missing.
