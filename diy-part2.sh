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

# 2) IPv4 单栈 —— 保留内核 CONFIG_IPV6=y（重要，不要再改成 n）
#    config/Config-build.in 里 `config IPV6 / def_bool y` 是强制符号。
#    Linux 6.18 把 nftables 的 reject 模块拆出 net/ipv6/netfilter/nft_reject_ipv6.ko，
#    Lean 的 kmod-nft-core 在 FILES 里无条件列了它。若把内核 IPv6 关成 n，
#    该 .ko 不会被编译，打包时必报：
#      ERROR: module '.../net/ipv6/netfilter/nft_reject_ipv6.ko' is missing.
#      make[3]: *** [modules/netfilter.mk:1195: .../kmod-nft-core_...ipk] Error 1
#    所以「默认网络是 IPv4」放在运行时实现，见 3)/4)，编译期保持上游默认。

# 3) IPv4 单栈：首次启动不生成 wan6 / ip6assign / IPv6 DNS
#    Lean 的 config_generate 全部靠 [ -e /proc/sys/net/ipv6 ] 判断
sed -i 's|\[ -e /proc/sys/net/ipv6 \]|[ -e /proc/sys/net/ipv6-disabled ]|g' \
    package/base-files/files/bin/config_generate

# 4) IPv4 单栈：运行时全局禁用 IPv6（内核模块仍编出来，但不激活任何接口）
#    OpenWrt 的 /etc/sysctl.conf 明确说明 /etc/sysctl.d/*.conf 会按序加载，
#    99- 排在 Lean 自带 10-default.conf 之后，可覆盖其中的 ipv6.forwarding=1。
mkdir -p package/base-files/files/etc/sysctl.d
cat > package/base-files/files/etc/sysctl.d/99-ipv4-only.conf <<'EOF'
# IPv4-only: kernel IPv6 modules are built (needed by kmod-nft-core packaging),
# but no interface is allowed to bring up an IPv6 address.
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
net.ipv6.conf.all.forwarding=0
net.ipv6.conf.default.forwarding=0
EOF

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

# 8) Linux 6.18 内核打包兼容 + 第三方 LuCI 包依赖瘦身
#    （在 make defconfig 之前执行，defconfig 会重新收集 package info）
python3 - <<'PY'
import pathlib

# 8.1 6.18 把 SHA1 拆成 crypto/sha1.ko + lib/crypto/libsha1.ko。
#     Lean master 的 crypto.mk 只列了前者，打包 kmod-crypto-sha1 时报
#     "Package kmod-crypto-sha1 is missing dependencies ... libsha1.ko" 并 exit 1。
#     官方 openwrt/main 已把两个 .ko 一起列入 FILES，这里对齐该写法。
p = pathlib.Path('package/kernel/linux/modules/crypto.mk')
s = p.read_text()
old = ("\t$(LINUX_DIR)/crypto/sha1.ko@ge6.18\n"
       "  AUTOLOAD:=$(call AutoLoad,09,sha1_generic@lt6.18 sha1@ge6.18)")
new = ("\t$(LINUX_DIR)/crypto/sha1.ko@ge6.18 \\\n"
       "\t$(LINUX_DIR)/lib/crypto/libsha1.ko@ge6.18\n"
       "  AUTOLOAD:=$(call AutoLoad,09,sha1_generic@lt6.18 sha1@ge6.18)")
if 'lib/crypto/libsha1.ko' in s:
    print('crypto.mk: 上游已包含 libsha1，跳过补丁')
elif old in s:
    p.write_text(s.replace(old, new, 1))
    print('crypto.mk: 已补 lib/crypto/libsha1.ko@ge6.18')
else:
    print('::warning::crypto.mk 结构与预期不同，未打补丁（上游可能已改写法）')

# 8.2 第三方 LuCI 页面的硬依赖在 Lean 25.12 下常无法满足（luci-compat /
#     luci-nginx / HIDDEN 的 i18n 分包等），make defconfig 会把整包清掉。
#     统一精简为 +luci-base；后端程序由 .config 单独选中，互不牵连。
def trim(path, key='LUCI_DEPENDS'):
    f = pathlib.Path(path)
    if not f.is_file():
        print('  跳过 %s（文件不存在）' % path)
        return
    lines = f.read_text().splitlines(keepends=True)
    out, i, hits = [], 0, 0
    while i < len(lines):
        line = lines[i]
        if line.startswith(key + ':='):
            hits += 1
            while line.rstrip('\n').rstrip().endswith('\\') and i + 1 < len(lines):
                i += 1
                line = lines[i]
            out.append(key + ':=+luci-base\n')
            i += 1
            continue
        out.append(line)
        i += 1
    f.write_text(''.join(out))
    print('  %s: 精简 %d 处 %s -> +luci-base' % (path, hits, key))

for f in ('package/luci-app-quickfile/Makefile',
          'package/luci-app-dockerman/Makefile',
          'package/luci-lib-docker/Makefile'):
    trim(f)

# 8.3 Clashoo：核心包上游 DEPENDS 里有 yq、coreutils-nohup、coreutils-timeout、
#     unzip、ip-full、一堆 kmod，在 Lean 25.12 的 metadata 扫描里被判为
#     "which does not exist"，make defconfig 会把 clashoo 及依赖它的
#     luci-app-clashoo 一起清掉（#2 日志 Step 9 报"未被选中"、
#     编译队列里两个包都出现 0 次）。
#     这里把 DEPENDS 精简到构建必需项，运行时工具改由 .config 显式选中。
def set_depends(path, value):
    f = pathlib.Path(path)
    if not f.is_file():
        print('  跳过 %s（文件不存在）' % path)
        return
    lines = f.read_text().splitlines(keepends=True)
    out, i, hits = [], 0, 0
    while i < len(lines):
        line = lines[i]
        stripped = line.lstrip()
        if stripped.startswith('DEPENDS:=') and not stripped.startswith('PKG_'):
            hits += 1
            indent = line[:len(line) - len(line.lstrip())]
            while line.rstrip('\n').rstrip().endswith('\\') and i + 1 < len(lines):
                i += 1
                line = lines[i]
            out.append(indent + 'DEPENDS:=' + value + '\n')
            i += 1
            continue
        out.append(line)
        i += 1
    f.write_text(''.join(out))
    print('  %s: DEPENDS 精简 %d 处 -> %s' % (path, hits, value))

set_depends('package/clashoo/Makefile',
            '$(GO_ARCH_DEPENDS) +ca-bundle +firewall4 +kmod-tun')
# LuCI 页面只保留 luci-base，避免 HIDDEN 的 i18n 分包与核心包形成循环牵连
set_depends('package/luci-app-clashoo/Makefile', '+luci-base')
PY

echo "==== 版本 / IPv4 单栈 / 主题定制结果 ===="
grep -n '25.12.2' include/version.mk | head -5 || true
echo -n "CONFIG_IPV6 保持上游默认："
sed -n '/config IPV6/,+1p' config/Config-build.in | tr '\n' ' ' || true
echo
echo -n "config_generate 已屏蔽的 IPv6 判断数："
grep -c '/proc/sys/net/ipv6-disabled' package/base-files/files/bin/config_generate || true
echo "运行时 IPv6 禁用配置："
cat package/base-files/files/etc/sysctl.d/99-ipv4-only.conf
echo "diy-part2 done."
