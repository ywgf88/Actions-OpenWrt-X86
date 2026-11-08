#!/bin/bash
#
# diy-part1.sh —— 在 ./scripts/feeds update -a 之前执行
# 工作目录：OpenWrt/LEDE 源码根目录
# 作用：把第三方插件源码放进 package/，让后续 feeds install / make defconfig 能扫描到
#
set -e

SRC=/tmp/openwrt-diy-src
rm -rf "$SRC"
mkdir -p "$SRC"

# 先清理同名包，避免和 feeds 里的包发生同名冲突
rm -rf package/luci-app-run package/luci-app-partexp package/luci-app-quickfile \
       package/luci-theme-aurora package/luci-theme-vantage \
       package/clashoo package/luci-app-clashoo \
       package/luci-app-dockerman package/luci-app-diskman package/luci-lib-docker

git_diy() { git clone --depth 1 -b "$2" "$1" "$3"; }

# 1) luci-app-run —— Run 安装器（兼容 25.12 的 apk）
git_diy https://github.com/wukongdaily/luci-app-run.git master "$SRC/run"
cp -rf "$SRC/run/luci-app-run" package/

# 2) luci-app-quickfile —— 轻量级网页文件管理器
git_diy https://github.com/sbwml/luci-app-quickfile.git main "$SRC/quickfile"
cp -rf "$SRC/quickfile/luci-app-quickfile" package/

# 3) luci-app-partexp —— 分区扩容
git_diy https://github.com/sirpdboy/luci-app-partexp.git main "$SRC/partexp"
cp -rf "$SRC/partexp/luci-app-partexp" package/

# 4) luci-theme-aurora —— 仓库根目录本身就是包
git_diy https://github.com/eamonxg/luci-theme-aurora.git master package/luci-theme-aurora
rm -rf package/luci-theme-aurora/.git

# 5) clashoo —— 核心 + LuCI 插件（两个包都要）
git_diy https://github.com/kenzok8/openwrt-clashoo.git main "$SRC/clashoo"
cp -rf "$SRC/clashoo/clashoo" "$SRC/clashoo/luci-app-clashoo" package/

# 6) Docker —— dockerman 及其依赖 luci-lib-docker
git_diy https://github.com/lisaac/luci-app-dockerman.git master "$SRC/dockerman"
cp -rf "$SRC/dockerman/applications/luci-app-dockerman" package/
git_diy https://github.com/lisaac/luci-lib-docker.git master "$SRC/libdocker"
cp -rf "$SRC/libdocker/collections/luci-lib-docker" package/

# 7) DiskMan —— 磁盘/分区管理
git_diy https://github.com/lisaac/luci-app-diskman.git master "$SRC/diskman"
cp -rf "$SRC/diskman/applications/luci-app-diskman" package/

# 8) luci-theme-vantage —— 只取主题；luci-app-vantage 是可选仪表盘，未启用
git_diy https://github.com/anothaDev/luci-theme-vantage.git main "$SRC/vantage"
cp -rf "$SRC/vantage/luci-theme-vantage" package/

# 说明：
#  - luci-theme-argon 由 coolsnowwolf/luci 的 openwrt-25.12 分支自带，不额外克隆，避免同名冲突
#  - passwall2 / passwall_packages 由 feeds.conf.default 的 src-git 提供，feeds update 时自动拉取

echo "==== 已注入 package/ 的第三方包 ===="
ls -1 package | grep -E '^(luci-|clashoo)' | sort || true

rm -rf "$SRC"
