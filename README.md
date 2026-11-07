# HG5585F 自编译固件（OpenWrt SNAPSHOT · Linux 7.3.1）

面向 **烽火 HG5585F（Airoha AN7581）** 光猫路由一体机的 OpenWrt 自编译树。
一条命令产出一套可刷的 `sysupgrade.itb` / `recovery.itb`，目标是**用全开源组件替换厂商 QWRT 固件**，
并把厂商固件里缺失的能力（NAT1 / FullCone）补回来。

当前产物：`fw-20261107-b49-ct`、`fw-20261107-b49-cu`（OpenWrt SNAPSHOT `r0-0c9a73e`，内核 **7.3.1**）。

---

## 1. 机型与硬件

| | `fiberhome_hg5585f-ct`（主力） | `fiberhome_hg5585f-cu`（试验） |
|---|---|---|
| SoC | Airoha AN7581，4×Cortex-A53 @1.05 GHz | 同左 |
| 内存 | 403 MB（无 swap，ubifs overlay） | 同左 |
| 存储 | pNAND + UBI + FIT 启动 | 同左 |
| 无线 | MT7916AN（`kmod-mt7915e` + `mt7916-firmware`，EEPROM 取自 factory nvmem） | 同左 |
| PON | 10G‑EPON 非对称（`epon-10g-1g`），CTC OAM + LOID，VLAN 995 拨号 | 同左 |
| 特色 | 板载 **2.5G PHY（GPY211C / `kmod-phy-maxlinear`）**，接 `gdm4` → `lan1` | 无 2.5G PHY |
| DTS | `an7581-fiberhome-hg5585f-ct.dts` | `an7581-fiberhome-hg5585f-cu.dts` |
| 产物 | `…-ct-squashfs-sysupgrade.itb` / `…-ct-initramfs-recovery.itb` | `…-cu-…` |

两个变体共用 `an7581-fiberhome-hg5585f-common.dtsi`，差异只在 2.5G PHY 与 DTS 变体文件。

---

## 2. 和别的固件有什么不同

### 2.1 对比原版 OpenWrt

原版 OpenWrt **没有**这台的机型支持，也没有 PON 栈和 NAT1：

| 能力 | 原版 OpenWrt | 本树 |
|---|---|---|
| 机型支持 | 无 | 补 DTS（5 个）、image 配方、U‑Boot/FIT 打包 |
| PON | 无 | 开源 `airoha-xpon` 驱动 + `ponctl` / `airoha-pond` + LuCI 页面 |
| NAT1（FullCone） | 无 | `kmod-nft-fullcone` + libnftnl/nftables/firewall4 三处补丁 |
| 内核 | 6.12/6.18 | **7.3.1**（`KERNEL_TESTING_PATCHVER`） |

### 2.2 对比 ImmortalWrt / lede 等分支

它们把同一颗 SoC 跑在更老的内核上，WiFi 用厂商 `mtwifi`，NAT1 多靠老式 `fullconenat`（iptables 时代）：

| 维度 | 常见分支 | 本树 |
|---|---|---|
| 内核 | 5.4 / 6.6 / 6.12 | **7.3.1**（含 airoha 目标补丁全量刷新） |
| 无线 | `mtwifi` 厂商驱动 + `l1profile.dat` 调参 | **mt76 原生**（`kmod-mt7915e`），802.11k/v 用标准开关 |
| 包管理 | opkg | **apk**（OpenWrt 25.12 主线） |
| LuCI | 旧版 ucode / Lua 混用 | **25.12 ucode** 分支 |
| NAT1 | `fullconenat`（iptables）或闭源 | **nftables 原生 fullcone 表达式** |

### 2.3 对比 QWRT（厂商 BSP）——最关键的取舍

QWRT 能用，是因为它带着一堆**闭源内核模块**；本树全部用开源实现，因此能力边界不同：

| 能力 | QWRT（闭源 BSP） | 本树（全开源） |
|---|---|---|
| 硬件 NAT 卸载 | ✅ `an7581-bsp-ppe.ko`（PPE/HNAT） | ❌ 无 blob，**不提供** |
| 软件 flowtable 卸载 | 需绕过（7 设备上限、PPPoE 下掉到 ~640M） | ✅ 标准 `nf_flow_table`，无厂商限制 |
| 无线驱动 | `mtwifi` 闭源 | mt76 开源 |
| 定制 Web 页（PPE 阈值、硬件 QoS） | ✅ | ❌ 用 LuCI 原生 |
| 可审计性 | 低（blob 多） | **高**（全部可编译、可 diff） |
| 升级可控性 | 跟随 QWRT 发版 | 自己控制内核与包集 |

**实测结论（5.4.302 的 QWRT 上，speedtest.cn）**：硬件卸载 632 Mbps、软件卸载修复后 **1022 Mbps**、无卸载 1026 Mbps。
PPE 模块里没有任何 `ppp/pppoe` 符号，PPPoE 流量进硬件表项就会被拖进半残路径 —— 这也是本树干脆不要硬件卸载的原因。

---

## 3. 软件构成

按层次看，镜像里的东西分六层：

| 层 | 组件 | 说明 |
|---|---|---|
| 基础 | procd / netifd / `apk` / ucode / musl | OpenWrt SNAPSHOT 基线 |
| 内核 | Linux **7.3.1**（airoha/an7581，492 行 target config） | `KERNEL_TESTING_PATCHVER:=7.3` |
| 网络 | mt76（MT7916）、`kmod-airoha-xpon` / `pon-frontend` / `paged-bosa`、`airoha-pond` / `ponctl` | PON 全开源栈 |
| 转发 | `nft-fullcone` + `kmod-nf-flow` + `kmod-nft-offload` + `firewall4` | NAT1 + 软件卸载 |
| 服务 | `nginx-ssl`（TLS 反代入口）、`ddns-scripts`（含 CF 脚本支持）、`honk`（eBPF/BTF 代理内核） | 替代 openclash/dae |
| 交互 | LuCI 25.12（中文）、`luci-theme-vantage` / `luci-theme-design`、`luci-app-pon` / `-cpufreq` / `-ddns` / `-honk` | 全中文界面 |
| 工具 | `curl` `ethtool` `htop` `tcpdump` `jq` `nand-utils` `ubi-utils` | 排障用 |

完整包集见 [`target/linux/airoha/image/an7581.mk`](target/linux/airoha/image/an7581.mk) 的 `DEVICE_PACKAGES`。

---

## 4. 四条关键实现

### 4.1 PON：开源栈替代厂商 blob

- 驱动来自 `feeds/pon_drivers`（`airoha-xpon` 等），用户态来自 `feeds/pon_userspace`；
- 7.3 上 `hex2bin()` 的声明从 `<linux/kernel.h>` 挪到 `<linux/hex.h>`，由 [`scripts/patch-pon-7.3.sh`](scripts/patch-pon-7.3.sh) 在编译前自动补 include；
- 身份（serial / LOID / CTC OUI / 模式）**不写进仓库**，首次启动从 `/etc/pon-identity`（0600）读取。

### 4.2 NAT1（FullCone）：nftables 原生表达式

`firewall4` 的 `option fullcone` 原本没有实现，本树补齐了完整链路：

```text
kmod-nft-fullcone   ← package/network/utils/fullconenat-nft（内核模块 + 4 个补丁）
libnftnl            ← 001-libnftnl-add-fullcone-expression-support.patch
nftables            ← 001-nftables-add-fullcone-expression-support.patch
firewall4           ← 001-firewall4-add-support-for-fullcone-nat.patch
```

运行时可见：

```text
nft list chain inet fw4 srcnat_wan
  meta nfproto ipv4 fullcone comment "!fw4: Handle wan IPv4 fullcone NAT srcnat traffic"
```

### 4.3 流量卸载：只用软件 flowtable

不碰厂商 PPE，走标准 `nf_flow_table`：

```text
flowtable ft { hook ingress priority filter; devices = { "br-lan", "pon0.995" }; counter }
```

7.3 原生内核没有“每张 flowtable 最多 7 个设备”的厂商限制，`fw4` 也不会因为设备数超限而整份规则集失败。

### 4.4 代理栈：honk

`honk` 基于 eBPF/BTF 在内核态做透明代理分流，镜像里带了完整 BTF 与 kprobe 支持（内核配置门禁会校验）：

```text
CONFIG_DEBUG_INFO_BTF / CONFIG_CGROUPS / CONFIG_CGROUP_BPF / CONFIG_KPROBES / CONFIG_NETKIT
```

---

## 5. 构建与持续集成

`.github/workflows/build-hg5585f-73.yml`，**cu / ct 双机型矩阵**，一次 push 出两套包：

```text
检查依赖 → 恢复工具链缓存 → 装 feeds → 打 PON 7.3 补丁 → defconfig
        → kernel_oldconfig → 内核配置门禁 → 冒烟编译（libnftnl/nftables/fullcone 源）
        → 全量编译 → 打日期+编号 → 校验“每机型各一张镜像” → 上传 artifact → 发布预发布
```

设计要点：

- **前置门禁**：内核配置在几分钟内校验 honk 所需符号，避免 4 小时后才发现；
- **冒烟编译**：`libnftnl` 编译 + `nftables` 打补丁 + fullcone 源码哈希校验，专治 autotools/哈希这类“晚期失败”；
- **镜像唯一性校验**：每个机型必须恰好一张 sysupgrade + 一张 recovery，防止重复文件；
- **只在成功时发布**：失败的构建不会产生空 Release；
- 工具链缓存键按机型 + 配置哈希；实测双机型并行一轮约 4–5 小时（首次无缓存更久）。

产物命名：`openwrt-airoha-an7581-fiberhome_hg5585f-<变体>-{squashfs-sysupgrade,initramfs-recovery}-<日期>-b<运行号>.itb`，
附 `sha256sums-<日期>-b<运行号>.txt`。

---

## 6. 当前验证状态

| 项 | CU（已刷） | CT |
|---|---|---|
| 内核 | `7.3.1` ✅ | 待刷（仍跑 QWRT 生产） |
| 系统 | `r0-0c9a73e` ✅ | — |
| NAT1 | `nft_fullcone` 已加载，2 条 fullcone 规则 ✅ | — |
| 软件卸载 | flowtable 已建（`br-lan` + `pon0.995`）✅ | — |
| PON | `ponctl`：`active_mode=epon-10g-1g`，`lifecycle=wait-line-sync` ✅ | — |
| 拨号 | PPPoE over `pon0.995` 已配置，待接光纤实测 | — |

刷机前请确认镜像 DTS 与机型一致（`ct` 镜像含 `fiberhome,hg5585f-ct`，`cu` 镜像含 `fiberhome,hg5585f-cu`）。

---

## 7. 刷机

```sh
# 常规升级（保留配置）
sysupgrade -v openwrt-airoha-an7581-fiberhome_hg5585f-<变体>-squashfs-sysupgrade-<tag>.itb

# 变砖恢复：U-Boot 里通过 TFTP 拉 initramfs-recovery.itb 启动，再 sysupgrade
```

升级前建议备份：`/etc/config/`、`/etc/pon-identity`、`/etc/wireless-cfg`、`/etc/root-passwd`。

---

## 8. 安全约定

**本仓库是公开的，不含任何凭据。** 以下文件在刷机时写入、权限 `0600`，永不入库：

| 文件 | 内容 |
|---|---|
| `/etc/pon-identity` | `PON_SERIAL` / `PON_LOID` / `PON_MODE` |
| `/etc/wireless-cfg` | `WIFI_PSK` / `WIFI_SSID_2G` / `WIFI_SSID_5G` |
| `/etc/root-passwd` | root 密码（首次启动由 `05-root-passwd` 应用） |

镜像不再内置 `/etc/shadow`；`base-files` 的 keep 机制保证 sysupgrade 后旧密码继续有效。
缺少上述文件时固件会保持“无凭据”的安全默认：PON 不注册、WiFi 不开启。

---

## 9. 已知限制

- **无硬件 NAT 卸载**：厂商 `an7581-bsp-ppe.ko` 是闭源 blob，本树不包含；需要极限 PPS 的场景请用软件 flowtable；
- **CU 无 2.5G PHY**：该口只在 CT 变体上启用；
- **mt76 无厂商私有调参**：QWRT 的 `l1profile.dat` 里那些 RRM/DBDC 私有项在 mt76 下没有等价开关，只用标准 802.11k/v；
- **内核为 testing 版本**：`KERNEL_TESTING_PATCHVER:=7.3`，升级需自行验证；迁移记录见 [`KERNEL-7.3.md`](KERNEL-7.3.md)。

---

## 10. 许可与致谢

基于 [OpenWrt](https://openwrt.org/)（GPL-2.0 / ISC 等，见 [`COPYING`](COPYING) 与 [`LICENSES/`](LICENSES)）。
PON 驱动与用户态来自 [pbs05/openwrt-pon-drivers](https://github.com/pbs05/openwrt-pon-drivers)、
[pbs05/openwrt-pon-userspace](https://github.com/pbs05/openwrt-pon-userspace)；
NAT1 内核模块来自 [fullcone-nat-nftables/nft-fullcone](https://github.com/fullcone-nat-nftables/nft-fullcone)；
主题与插件来自 LuCI、vantage、honk 等上游项目。

本树仅为个人自用固件，**刷机有风险，自担后果**。
