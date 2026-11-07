# HG5585F 固件源码树（OpenWrt）

面向 **烽火 HG5585F（Airoha AN7581）** 光猫路由一体机的 OpenWrt 源码树：
补齐官方 OpenWrt 没有的机型支持（DTS / 镜像配方 / PON 栈），并在此基础上做出可长期使用的
自编译固件，目标是用全开源组件替换厂商 QWRT。

> **想直接拿固件**：本仓库的构建与发布都在 **`honk` 分支**进行，
> 每次 CI 会产出 `fw-<日期>-b<编号>-{ct,cu}` 的预发布包（含 sysupgrade / recovery / sha256sums）。
> 默认分支 `hg5585f` 只是机型支持基线，不带 NAT1 等生产特性 —— 见下面的分支表。

---

## 1. 分支说明

| 分支 | 用途 | 内核 | 关键内容 |
|---|---|---|---|
| **`hg5585f`**（默认） | 机型支持基线 | 6.18（7.3 为 `KERNEL_TESTING_PATCHVER`） | DTS、image 配方、PON 栈、文件覆盖层、LuCI 中文与主题 |
| **`honk`** | **生产构建分支（推荐）** | **7.3.1** | 基线 + NAT1（nft-fullcone）+ 软件卸载 + CI 双机型发版 |
| `airoha`/`ath79`/`bcm53xx`/`mediatek`/`ramips`/`ipq806x`/`qualcommax`/`qualcommbe`/`generic` | 各 target 的 7.3 迁移分支 | 7.3 | 按 target 批量刷新补丁与配置 |
| `openwrt618` | 6.18 快照 | 6.18 | 迁移前的对照基线 |

构建生产固件请切到 `honk`：

```bash
git clone -b honk https://github.com/Bernardxu123/openwrt73-hg5585f.git
cd openwrt73-hg5585f
cp configs/hg5585f-cu.config .config     # 或 hg5585f-ct.config
make defconfig
```

---

## 2. 机型与硬件

| | `fiberhome_hg5585f-ct`（主力） | `fiberhome_hg5585f-cu`（试验） |
|---|---|---|
| SoC | Airoha AN7581，4×Cortex-A53 @1.05 GHz | 同左 |
| 内存 | 403 MB（无 swap，ubifs overlay） | 同左 |
| 存储 | pNAND + UBI + FIT 启动（pNAND / U‑BI） | 同左 |
| 无线 | MT7916AN（`kmod-mt7915e` + `mt7916-firmware`，EEPROM 来自 factory nvmem） | 同左 |
| PON | 10G‑EPON 非对称（`epon-10g-1g`），CTC OAM + LOID，VLAN 995 拨号 | 同左 |
| 特色 | 板载 **2.5G PHY（GPY211C / `kmod-phy-maxlinear`）**，`gdm4` → `lan1` | 无 2.5G PHY |
| DTS | `an7581-fiberhome-hg5585f-ct.dts` | `an7581-fiberhome-hg5585f-cu.dts` |

两个变体共用 `an7581-fiberhome-hg5585f-common.dtsi`，差异只在 2.5G PHY 与变体 DTS。

---

## 3. 和别的固件有什么不同

### 3.1 对比原版 OpenWrt

原版没有这台机型：机型支持、PON 栈、NAT1 都是本树补的（NAT1 在 `honk` 分支）。

| 能力 | 原版 OpenWrt | 本树 |
|---|---|---|
| 机型支持 | 无 | DTS（5 个）+ image 配方 + FIT 打包 |
| PON | 无 | 开源 `airoha-xpon` + `ponctl`/`airoha-pond` + LuCI 页面 |
| NAT1（FullCone） | 无 | nftables 原生 fullcone 表达式（`honk`） |
| 内核 | 6.12/6.18 | 6.18，或 7.3.1（`honk`） |

### 3.2 对比 ImmortalWrt / lede 等分支

| 维度 | 常见分支 | 本树（`honk`） |
|---|---|---|
| 内核 | 5.4 / 6.6 / 6.12 | **7.3.1** |
| 无线 | `mtwifi` 厂商驱动 + `l1profile.dat` | **mt76 原生**，802.11k/v 用标准开关 |
| 包管理 | opkg | **apk**（OpenWrt 25.12 主线） |
| LuCI | 旧版 ucode / Lua 混用 | **25.12 ucode** |
| NAT1 | `fullconenat`（iptables）或闭源 | **nftables 原生 fullcone** |

### 3.3 对比 QWRT（厂商 BSP）

QWRT 依赖闭源内核模块；本树全部开源，所以取舍不同：

| 能力 | QWRT（闭源 BSP） | 本树（全开源） |
|---|---|---|
| 硬件 NAT 卸载 | ✅ `an7581-bsp-ppe.ko`（PPE/HNAT） | ❌ 无 blob，不提供 |
| 软件 flowtable | 需绕过（7 设备上限、PPPoE 下 ~640M） | ✅ 标准 `nf_flow_table` |
| 无线驱动 | `mtwifi` 闭源 | mt76 开源 |
| 厂商定制页 | PPE 阈值、硬件 QoS | LuCI 原生 |
| 可审计性 | 低 | 高（可编译、可 diff） |

实测（QWRT 5.4.302，speedtest.cn）：硬件卸载 632 Mbps、软件卸载修复后 **1022 Mbps**、无卸载 1026 Mbps。
PPE 模块内没有任何 `ppp/pppoe` 符号，PPPoE 流量进硬件表项会掉进半残路径 —— 这是本树不要硬件卸载的直接原因。

---

## 4. 软件构成（`honk` 分支镜像）

| 层 | 组件 |
|---|---|
| 基础 | procd / netifd / `apk` / ucode / musl |
| 内核 | Linux **7.3.1**（airoha/an7581） |
| 网络 | mt76（MT7916）、`kmod-airoha-xpon` / `pon-frontend` / `paged-bosa`、`airoha-pond` / `ponctl` |
| 转发 | `kmod-nft-fullcone` + `kmod-nf-flow` + `kmod-nft-offload` + 打过补丁的 `firewall4` |
| 服务 | `nginx-ssl`、`ddns-scripts`、`honk`（eBPF/BTF 代理内核） |
| 交互 | LuCI 25.12（中文）、`luci-theme-vantage` / `luci-theme-design`、`luci-app-pon`/`-cpufreq`/`-ddns`/`-honk` |
| 工具 | `curl` `ethtool` `htop` `tcpdump` `jq` `nand-utils` `ubi-utils` |

包集定义见 `target/linux/airoha/image/an7581.mk`；7.3 迁移记录见 `KERNEL-7.3.md`。

---

## 5. 构建与发布

CI 工作流 `.github/workflows/build-hg5585f-73.yml` 监听 `hg5585f` 与 `honk`，`honk` 上跑 **ct/cu 双机型矩阵**：

```text
依赖 → 工具链缓存 → feeds → PON 7.3 补丁 → defconfig → kernel_oldconfig
     → 内核配置门禁 → 冒烟编译（libnftnl / nftables / fullcone 源）
     → 全量编译 → 打日期+编号 → 校验每机型各一张镜像 → artifact → 预发布
```

产物命名：

```text
openwrt-airoha-an7581-fiberhome_hg5585f-<变体>-squashfs-sysupgrade-<日期>-b<编号>.itb
openwrt-airoha-an7581-fiberhome_hg5585f-<变体>-initramfs-recovery-<日期>-b<编号>.itb
sha256sums-<日期>-b<编号>.txt
```

刷机：

```sh
sysupgrade -v openwrt-...-squashfs-sysupgrade-<tag>.itb    # 常规升级，保留配置
# 变砖恢复：U-Boot 里 TFTP 引导 initramfs-recovery.itb，再 sysupgrade
```

---

## 6. 安全约定

**本仓库公开，不含任何凭据。** 以下文件在刷机时写入、权限 `0600`，永不入库：

| 文件 | 内容 |
|---|---|
| `/etc/pon-identity` | `PON_SERIAL` / `PON_LOID` / `PON_MODE` |
| `/etc/wireless-cfg` | `WIFI_PSK` / `WIFI_SSID_2G` / `WIFI_SSID_5G` |
| `/etc/root-passwd` | root 密码（由 `05-root-passwd` 首次启动应用） |

镜像**不内置** `/etc/shadow`；缺少上述文件时固件保持“无凭据”的安全默认（PON 不注册、WiFi 不开启）。

---

## 7. 已知限制

- **无硬件 NAT 卸载**：厂商 PPE 是闭源 blob，本树不含；
- **CU 无 2.5G PHY**：该口只在 CT 变体启用；
- **mt76 无厂商私有调参**：QWRT 的 RRM/DBDC 私有项没有等价开关；
- **7.3 为 testing 内核**：以 `KERNEL_TESTING_PATCHVER` 启用，升级需自行验证。

---

## 8. 许可与致谢

基于 [OpenWrt](https://openwrt.org/)（见 `COPYING` 与 `LICENSES/`）；
PON 驱动/用户态来自 [pbs05/openwrt-pon-drivers](https://github.com/pbs05/openwrt-pon-drivers) 与
[pbs05/openwrt-pon-userspace](https://github.com/pbs05/openwrt-pon-userspace)；
NAT1 内核模块来自 [fullcone-nat-nftables/nft-fullcone](https://github.com/fullcone-nat-nftables/nft-fullcone)。

个人自用固件，刷机有风险，自担后果。
