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
PY

# 8.3 clashoo 的 LuCI 包硬依赖 HIDDEN 的 i18n 分包，25.12 下无法解析
if [ -f package/luci-app-clashoo/Makefile ]; then
  sed -i 's/ +luci-i18n-clashoo-zh-cn//g' package/luci-app-clashoo/Makefile
fi

echo "==== 版本 / IPv6 / 主题定制结果 ===="
grep -n '25.12.2' include/version.mk | head -5 || true
sed -n '/config IPV6/,+2p' config/Config-build.in || true
echo -n "config_generate 已屏蔽的 IPv6 判断数："
grep -c '/proc/sys/net/ipv6-disabled' package/base-files/files/bin/config_generate || true
echo "diy-part2 done."
