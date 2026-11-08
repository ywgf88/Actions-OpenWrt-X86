# Actions-OpenWrt-X86

基于 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) 模板（[教程](https://p3terx.com/archives/build-openwrt-with-github-actions.html)）改造的 **X86_64 云编译配置**：Lean's OpenWrt 源码、版本标识 25.12.2、默认 IPv4 单栈、指定插件与双主题。

## 一、模板机制（教程要点）

| 文件 | 作用 | 执行时机 |
|---|---|---|
| `.github/workflows/openwrt-builder.yml` | 定义环境变量与编译流水线 | 每次 Run workflow |
| `feeds.conf.default` | 覆盖源码自带的 feeds 列表 | Clone 源码后、Update feeds 前 |
| `diy-part1.sh` | 注入第三方软件包源码到 `package/` | Update feeds **之前** |
| `diy-part2.sh` | 改源码默认值（主题、时区、IPv6、版本号） | Install feeds **之后**、载入 `.config` 之后 |
| `.config` | `make defconfig` 的输入，决定目标架构与选包 | 编译前 |
| `files/`（可选） | files 大法，直接覆盖进固件根文件系统 | 编译前 |

产物在 Actions 的 Artifacts，以及（编译成功时）Releases 页面。

## 二、⚠️ 关于「版本 25.12.2」的口径

Lean's OpenWrt (`coolsnowwolf/lede`) **只有 `master` 分支，没有 `v25.12.2` tag**；它的 `include/version.mk` 默认写的是 `24.10.5`，但 `feeds.conf.default` 的 LuCI 源已经切到 `openwrt-25.12` 分支，内核为 6.18 —— 属于基于 25.12 的滚动源码。

本配置的处理方式：

- `REPO_URL` = `coolsnowwolf/lede`，`REPO_BRANCH` = `master`（保持 Lean 源码）
- `diy-part2.sh` 把 `include/version.mk` 的 `24.10.5` 替换为 `25.12.2`
- `.config` 里写入 `CONFIG_VERSION_NUMBER="25.12.2"`、`CONFIG_VERSION_REPO=.../25.12.2`

也就是说 **25.12.2 是固件显示/仓库版本号，不是官方发行版的精确源码快照**。如果你要的是"官方 OpenWrt 25.12.2 原版源码"，把 workflow 的两行改成：

```yaml
  REPO_URL: https://github.com/openwrt/openwrt
  REPO_BRANCH: v25.12.2
```

但那样就不再是 Lean 源码，`helloworld`、`autocore-x86` 等 Lean 专属包和第三方的兼容性需要重新验证。

## 三、插件来源（均已实测可克隆）

| 需求 | 包名 | 来源 | 引入方式 |
|---|---|---|---|
| Run 安装器 | `luci-app-run` | `wukongdaily/luci-app-run` (master) | diy-part1 clone → `package/` |
| 文件管理 | `luci-app-quickfile` | `sbwml/luci-app-quickfile` (main) | diy-part1 clone → `package/` |
| 极光主题 | `luci-theme-aurora` | `eamonxg/luci-theme-aurora` (master) | diy-part1 clone → `package/` |
| 分区扩容 | `luci-app-partexp` | `sirpdboy/luci-app-partexp` (main) | diy-part1 clone → `package/` |
| PassWall2 | `luci-app-passwall2` | `Openwrt-Passwall/openwrt-passwall2` + `openwrt-passwall-packages` (main) | `feeds.conf.default` 的 src-git |
| Clashoo | `clashoo` / `luci-app-clashoo` | `kenzok8/openwrt-clashoo` (main) | diy-part1 clone → `package/` |
| Docker | `luci-app-dockerman` / `luci-lib-docker` / `docker` / `dockerd` | `lisaac/...` + Lean packages feed | diy-part1 clone + feeds |
| DiskMan | `luci-app-diskman` | `lisaac/luci-app-diskman` (master) | diy-part1 clone → `package/` |
| Argon 主题 | `luci-theme-argon` | `coolsnowwolf/luci` (openwrt-25.12) | feed 自带，不额外 clone（避免同名冲突） |
| Vantage 主题 | `luci-theme-vantage` | `anothaDev/luci-theme-vantage` (main) | diy-part1 clone → `package/` |

> 旧地址 `xiaorouji/openwrt-passwall2` 已 404，本配置用的是迁移后的组织地址。

## 四、IPv4 单栈怎么做的

1. `diy-part2.sh` 把 `config/Config-build.in` 的 `config IPV6 / def_bool y` 改成 `def_bool n`
2. `.config` 里 `# CONFIG_IPV6 is not set` 并关闭 `odhcp6c` / `odhcpd-ipv6only` / `luci-proto-ipv6` / `ipv6helper` 等
3. `diy-part2.sh` 把 `config_generate` 中所有 `[ -e /proc/sys/net/ipv6 ]` 判断改成不存在的路径，首次启动就不会生成 IPv6 地址段、wan6 和 ip6assign
4. 默认 LAN 仍是 `192.168.1.1`，时区改为 `CST-8`，默认主题改为 Argon

## 五、部署到你的 GitHub（fork + 推送）

### 方式 A：一键脚本（推荐）

```bash
GITHUB_USER=你的用户名 GITHUB_TOKEN=ghp_xxx bash deploy-to-github.sh
```

PAT 需要 `repo` + `workflow` 权限。脚本会：调用 fork API 创建 `Actions-OpenWrt-X86`（已存在则复用）→ 克隆 → 覆盖本目录 5 个配置文件 → 提交推送 → 触发 `workflow_dispatch`。令牌只从环境变量读取，不落盘到 `.git/config`。可用 `REPO_NAME` 改仓库名。

> fork 出来的仓库 GitHub 可能默认禁用 Actions，第一次需要到 Actions 页面点一次启用按钮。

### 方式 B：手动

1. 打开 <https://github.com/P3TERX/Actions-OpenWrt> 点 **Fork**（教程原文用的是 *Use this template*，两者都能用，本配置按 fork 准备）
2. 把本目录的 `.config`、`feeds.conf.default`、`diy-part1.sh`、`diy-part2.sh`、`README.md` 和 `.github/workflows/openwrt-builder.yml` 覆盖/上传到 fork 仓库根目录
3. Settings → Actions → General → Workflow permissions 选 **Read and write permissions**（否则上传到 Releases 会报 `Resource not accessible by integration`）
4. Actions → `OpenWrt Builder X86` → **Run workflow**

## 六、首次编译检查清单

- `Verify configuration` 步骤会列出每个插件是否被 `make defconfig` 保留；出现 `::warning:: xxx 未被选中` 说明该包名或源码目录有问题，先按这一行排查，不用等编译 1 小时
- 全部 feed 源（Lean 6 个 + PassWall 2 个）已用 `git ls-remote` 实测可克隆；若日后上游改名，`Update feeds` 会先失败
- 第三方插件随上游源码变动，**首次编译建议只看 Artifacts**，成功后再启用 Release 上传
- 若 `Install feeds` 出现 `duplicate package` / 同名包警告（常见于 `helloworld` feed 与 clashoo 的核心包），可把 `feeds.conf.default` 里的 `src-git helloworld` 一行注释掉再试
- `docker` 按「引擎 + 管理界面」整套安装：`docker`、`dockerd`、`luci-app-dockerman`、`luci-lib-docker`、`ttyd`；`luci-lib-ip` 由 Lean 的 LuCI feed 提供
- workflow 已做的加固：补 `permissions`、编译失败不再误写 `status=success`、收尾步骤绑定编译成功状态、去掉模板里引用了未定义变量的 `UPLOAD_GOFILE` 行、去掉 `python2.7`（ubuntu-22.04 上装不上）、`upload-artifact` 固定 v4、调试期注释掉自动删除运行记录

### 已修复：Linux 6.18 的 `kmod-crypto-sha1` 打包失败

Lean master 的 `package/kernel/linux/modules/crypto.mk` 只把 `crypto/sha1.ko@ge6.18` 列入 `kmod-crypto-sha1` 的 `FILES`，漏了 6.18 新增的 `lib/crypto/libsha1.ko`。内核模块其实编出来了，但打包时依赖检查报：

```
Package kmod-crypto-sha1 is missing dependencies for the following libraries:
libsha1.ko
make[3]: *** [modules/crypto.mk:1055: .../kmod-crypto-sha1_6.18.62-1_x86_64.ipk] Error 1
```

`diy-part2.sh` 第 8 段按官方 `openwrt/main` 的写法把该模块补进 `FILES`。`Verify configuration` 里加了自检：补丁未生效会直接 `::error::` 快速失败，不用白等两小时编译。

### 已修复：第三方 LuCI 包被 `make defconfig` 清掉

Lean 25.12 下 `luci-compat` / `luci-nginx` / HIDDEN 的 i18n 分包这类硬依赖常无法满足，`defconfig` 会把整个 LuCI 包从 `.config` 移除（Step 9 显示"未被选中"）。`diy-part2.sh` 把 `luci-app-quickfile`、`luci-app-dockerman`、`luci-lib-docker` 的 `LUCI_DEPENDS` 精简为 `+luci-base`，并去掉 `luci-app-clashoo` 对 i18n 分包的硬依赖；后端程序由 `.config` 单独选中，页面与后端互不牵连。

### quickfile 的降级开关

`sbwml/luci-app-quickfile` 仓库里 `luci-app-quickfile/`（LuCI 页面）和 `quickfile/`（Rust/Axum 后端）是两个独立包，`diy-part1.sh` 已同时注入。后端需要 Rust 工具链与 `r2.cooluc.com` 源码包；若 Step 10/11 因它失败，删掉 `.config` 里的 `CONFIG_PACKAGE_quickfile=y` 一行即可降级，其余修复不受影响。

## 七、产物

`bin/targets/x86/64/` 下的 `combined.img.gz` / `combined-efi.img.gz` / squashfs / ext4 镜像，打包在 Artifacts `OpenWrt_firmware_x86_64_<时间戳>`；编译成功时同步发到 Releases。
