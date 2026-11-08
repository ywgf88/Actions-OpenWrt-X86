#!/bin/bash
#
# diy-part2.sh —— 在 ./scripts/feeds install -a 且载入 .config 之后执行
# 工作目录：OpenWrt/LEDE 源码根目录
# 作用：版本标识、IPv4 单栈、默认主题、时区等源码级定制
#
set -e

# 1) 版本标识 25.12.2
#    Lean 源码 include/version.mk 默认写的是 24.10.5，这里统一替换
sed -i 's/24\.10\.5/25.12.2/g' include/version.mk

# 2) IPv4-only：把 Kconfig 里 `config IPV6 / def_bool y` 改成默认 n
#    这样 make defconfig 不会把 IPv6 重新打开
sed -i '/^[[:space:]]*config IPV6$/,+1 s/def_bool y/def_bool n/' config/Config-build.in

# 3) IPv4-only：首次启动不生成 IPv6 地址段 / wan6 / ip6assign
#    Lean 的 config_generate 全部靠 [ -e /proc/sys/net/ipv6 ] 判断
sed -i 's|\[ -e /proc/sys/net/ipv6 \]|[ -e /proc/sys/net/ipv6-disabled ]|g' \
    package/base-files/files/bin/config_generate

# 4) 默认主题设为 Argon（Lean 的 LuCI 集合默认依赖 bootstrap）
if [ -d feeds/luci/collections ]; then
  find feeds/luci/collections -name Makefile \
    -exec sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' {} \;
fi

# 5) 时区设为中国标准时间
sed -i "s/timezone='GMT0'/timezone='CST-8'/" package/base-files/files/bin/config_generate

# 6) 主机名（按需取消注释）
# sed -i 's/OpenWrt/X86-OpenWrt/g' package/base-files/files/bin/config_generate

# 7) 默认 LAN 地址保持 192.168.1.1（如需修改，取消注释）
# sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/bin/config_generate

echo "==== 版本 / IPv6 / 主题定制结果 ===="
grep -n '25.12.2' include/version.mk | head -5 || true
sed -n '/config IPV6/,+2p' config/Config-build.in || true
echo -n "config_generate 已屏蔽的 IPv6 判断数："
grep -c '/proc/sys/net/ipv6-disabled' package/base-files/files/bin/config_generate || true
echo "diy-part2 done."
