# qualcommax 7.3 port comparison

Comparison of this tree's qualcommax 7.3 port against
[JuliusBairaktaris/openwrt-ppe-nss, branch `qualcommax-7.3`](https://github.com/JuliusBairaktaris/openwrt-ppe-nss/tree/qualcommax-7.3).

## Context

Both trees are sibling branches of the same effort: this tree carries Julius's
patches (our `0955`/`0956` are authored by him) plus the structured 4-commit
port; his `qualcommax-7.3` branch (commit 87e2711, Oct 7 2026 — authored before
7.3 final on Oct 18) took a different route.
`target/linux/qualcommax/Makefile` is byte-identical in both
(KERNEL_PATCHVER 6.18 + KERNEL_TESTING_PATCHVER 7.3, Makefile:11-12).
42 of the patch files are byte-identical; the rest are the same content at
different series positions (e.g. our `0122/0123/0130` are his with pure offset
shifts caused by our 0084 CMN-PLL series adding content to `ipq8074.dtsi`
first).

## Similarities (same design, verified)

- **Patch architecture**: both carry the MPD/WCSS-secure-PIL remoteproc stack
  (0803/0805/0811/0812/0818-19), TMEL QMP mailbox, uniphy-28lp PCIe/USB3 PHY
  series, dwc3 flatten-usb DTS series, ath11k WLAN nodes, qpic-NAND and
  cmdline-replacement hacks. Our `00730-01` (TME-L QMP header) is literally
  folded into his `0184` (+68-line `/dev/null` hunk) — same content.
- **Driver layout**: both carry `qca_edma`/`qca_ppe` in
  `target/linux/qualcommax/files/`, the same `ess.dtsi`/`-512m.dtsi` overlay
  approach, and the same upstream-DTS patch series for board support.
- **Same oldconfig mechanics**: both `config-6.18:418` record
  `# CONFIG_QCOM_80211AX_PPE is not set` with `=y` in subtarget
  `config-default` (ipq60xx/ipq807x) — the config-default override works
  identically.

## Differences, with verdicts

### 1. DSA tagging — in-band `qca-etype` (ours) vs out-of-band skb-extension tag (theirs)

Ours: new `qca-etype` protocol where the QCA header sits behind an 802.1AD
ethertype (patches-7.3/0955, 0956), set via `dts/ipq8074-rt-ax89x.dts:587`,
plus strip/insert in `files/.../qca_edma.c:649-668` (RX) and `:1016-1020`
(TX); PPE-as-DSA returns `DSA_TAG_PROTO_QCA` (qca_ppe_main.c:617-621).

Theirs: the 2022 Maxime Chevallier RFC (`0950`, `DSA_TAG_PROTO_OOB`, value 37)
carried via `SKB_EXT_DSA_OOB` skb extensions (`qca_edma.c:587/664/802/847`,
qca_ppe_main.c:509-515). `tag_oob.c` does **not** exist in v7.3 (verified
against pristine) — it is a never-merged RFC with known per-packet
`skb_ext_add` allocation cost, while ours uses a *real QCA8K hardware mode*
(header behind length/type) and keeps EDMA csum/TSO offload working. Ours'
cost is a 12-byte memmove per packet and a redundant software tag round-trip;
his avoids that but adds extension allocations and core `skbuff.c` churn.

**Verdict: ours superior** — hardware-native mode, no hot-path allocations,
confined to `tag_qca.c`/`qca8k.c`. Caveat: his tree builds no `tag_qca`
(config-7.3:325 only has TAG_OOB) while his board DTS still declares qca8337
DSA switches — how the inner cascade link gets tagged is not visible in his
patch set (untested).

### 2. CMN PLL wiring (ipq8074)

Ours carries a complete upstream-shaped series: 0084-01 corrects the NSS NoC
bias to 461.5 MHz (v7.3 `ipq-cmn-pll.c:135` still ships the wrong 416.5 MHz),
0084-02/03 add binding + fw_name parent resolution, 0084-04 adds the node to
upstream `ipq8074.dtsi`, and 0148 does the same for ipq6018.

His tree has **no CMN-PLL patch at all**; the node lives only in his
out-of-tree `files/.../ipq8074-ess.dtsi:10` and GCC resolves bias clocks via
legacy global-name fallback. Worse, his `0147` adds 6 UNIPHY clocks to the GCC
node **without any binding update**, and pristine v7.3 `qcom,gcc-ipq8074.yaml`
allows exactly 4 clock items — schema violation. Ours updates the binding in
both 0084-02 and 0147.

**Verdict: ours clearly superior** (schema-consistent, upstream-shaped, fixes
a real upstream rate bug).

### 3. pinctrl/clk v7.4 backports

His 0092 (`pwm3 on gpio13`) and 0093 (`PWM groups`) are **already in pristine
7.3** — `pinctrl-ipq5018.c:565-566` has
`pwm3_groups = {gpio45, gpio30, gpio13}` and `:692` has
`PINGROUP(13, …, pwm3, …)`; both patches fail to apply against 7.3 (2/2 and
6/6 hunks skipped in dry-run). We correctly dropped both in 2/4
(readme lines 29-30). His 0094 (24 MHz USB UTMI rate) *is* legitimately new
(v7.3 `gcc-ipq5018.c:1262-1265` lacks the 24 MHz entry) and we don't carry it.

**Verdict: ours superior on 0092/0093; his 0094 is a genuine addition we
lack.**

### 4. ipq5018 USB3 — complementary halves of one fix

Ours carries the dwc3 core/glue ref-clock plumbing (0140/0141: pass mock_utmi
rate to the core, needed since flattened dwc3 sets `ignore_clocks_and_resets`).
His carries the 24 MHz requirement (0094 clk-table entry +
`assigned-clock-rates = <24000000>` in his 0142/0160 DTS — his 0142's single
changed block vs ours is exactly that line) but **no ref-clock plumbing**. Per
the series commit messages, the SoC needs *both* (rate passed to core for
GUCTL, and 24 MHz for reliable enumeration). Neither tree is complete.

**Verdict: they should be merged.** If forced to pick which half is more
load-bearing: his (the hardware rate requirement), but ours' half is what the
upstream series exists for.

### 5. uniphy PCIe/USB3 PHY series shape

Ours: 5 consolidated patches (0151-0155) with combined power_on/off branching
on `PHY_IS_USB3`. His: 7 patches matching the current upstream v4 submission
(Link `20260908-ipq5018-usb3-v4`), split per-mode ops/data
(`ipq5018_pcie_data`/`ipq5018_usb3_data`, separate `qcom_uniphy_usb3_ops`),
plus the cleanups we folded away. His also has the more accurate Kconfig help
text; ours' 0151 describes the combo driver as "USB Super-Speed UNIPHY".

**Verdict: his series shape superior for future upstream tracking** (rebases
onto the actual upstream submission); ours is functionally equivalent but a
locally-evolved variant.

### 6. config-7.3 hygiene

Ours accepted oldconfig defaults wholesale: full `CONFIG_PREEMPT=y`
(config-7.3:510-514; 6.18 built PREEMPT_NONE per
`config/Config-kernel.in:1599-1602` — the silent arm64 NONE→PREEMPT change he
diagnosed and corrected to `PREEMPT_LAZY`, config-7.3:473-476),
`GPIO_SHARED_PROXY=m` (:248 — risky: built-in shared-GPIO consumers probe at
boot; his `=y` at :214 is correct), dead `ARM64_PTR_AUTH/SVE` entries the A53
cannot implement, and ~40 `=y/=m` drivers for unrelated SoCs (X1E80100,
Kaanapali, Glymur, SM8750…). He pruned all of that, replaced
`CRYPTO_DEV_QCOM_RNG` with `HW_RANDOM_QCOM=y` (:230 vs our :264 not-set), and
demoted userless crypto modes to kmods.

**Verdict: his config superior on nearly every axis** (fidelity, size,
correctness); our 4/4 commit carries no message justifying the deviations.

### 7. PPE feature scope

Ours builds 7 objects including `qca_ppe_flow_offload.c` (2902 lines), ACL,
debugfs (18,244 lines total) and ships `package/network/config/qca-ppe-qos`;
his builds 3 objects (5,986 lines) and has **no in-tree NSS/ECM packages**
despite the repo's stated purpose.

**Verdict: ours superior in functionality** (working hw flow offload path
in-tree), though it is a feature difference, not a 7.3-port-quality one.

### 8. Ours-only functional fixes he lacks

- `0818` skip-MSA-lock for the IPQ5018 internal radio (his `0805:258` calls
  `qcom_scm_msa_lock()` unconditionally — his ipq5018 internal-radio WiFi will
  hit the `-EINVAL` on PASID 0x112 described in our commit message),
- `0314` spi-gpio spidelay (needed by our aw1000/fritzbox-4050/wax630 class
  boards),
- `0715` ipq5018 mdio vendor compatible (only needed if SSDK is used).

**Verdict: ours superior** where the hardware needs them; 0715 is optional.

### 9. One real bug he fixed that we still carry

His `0121` corrected the ipq8074 WLAN node unit address to `wifi@c000000`
matching its `reg = <0xc000000 0x2000000>`; ours still ships the inherited
6.18 mismatch `wifi@c0000000` vs reg `0xc000000` (patches-7.3/0121:23 vs :25 —
also inconsistent in patches-6.18). Given both SoCs share the WCSS layout
(`q6v5_wcss@cd00000` sits inside the 0xc000000–0xdfffffff window in both 0120
and 0906), **his fix is correct — we should adopt it** (inferred from the
memory map, not proven by boot test).

### 10. Process

Ours: 4-commit series + 154-line `readme.qualcommax.md` documenting every
removal/refresh — bisectable and reviewable. His: one mega-commit on a
71k-commit fork with no readme, carrying stale v7.4 patches against 7.3 final.

**Verdict: ours superior** as a port methodology.

## Net

Ours is the stronger 7.3 port overall (DSA approach, CMN PLL, backport
hygiene, process); his wins on config-7.3 hygiene, the uniphy v4 series
fidelity, the 0094 USB clk fix, and the 0121 unit-address fix. The two trees'
USB-UTMI halves are complementary and both incomplete.
