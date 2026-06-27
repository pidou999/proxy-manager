#!/usr/bin/env bash
#
# Proxy Manager — sing-box 升级脚本
# 维护者用：下载最新 sing-box 并替换 bin/sing-box
# 用法：bash tools/update-sing-box.sh [version]
#       不传 version 则取 GitHub 最新版
#

set -e

DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"

BIN_PATH="$DIR/bin/sing-box"

# 备份当前版本
if [ -f "$BIN_PATH" ]; then
    cp "$BIN_PATH" "$BIN_PATH.bak.$(date +%s)"
    echo "✅ 已备份当前 sing-box 到 $BIN_PATH.bak.<timestamp>"
fi

# 检测架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  A="amd64" ;;
    aarch64) A="arm64" ;;
    armv7l)  A="armv7" ;;
    *) echo "❌ 不支持的架构: $ARCH"; exit 1 ;;
esac

# 取版本号
if [ -n "$1" ]; then
    VERSION="$1"
else
    echo "🔍 查询 GitHub 最新版本..."
    VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | \
        grep '"tag_name"' | head -1 | cut -d'"' -f4 | sed 's/^v//')
    if [ -z "$VERSION" ]; then
        echo "❌ 获取版本失败，请手动指定：bash tools/update-sing-box.sh 1.13.13"
        exit 1
    fi
fi

echo "📥 下载 sing-box v$VERSION ($A)..."
URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-linux-${A}.tar.gz"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

curl -sL "$URL" | tar xz -C "$TMPDIR"

# 找到二进制
BIN_FILE=$(find "$TMPDIR" -name 'sing-box' -type f -executable | head -1)
if [ -z "$BIN_FILE" ]; then
    echo "❌ 下载后未找到 sing-box 二进制"
    exit 1
fi

# 替换
mv "$BIN_FILE" "$BIN_PATH"
chmod +x "$BIN_PATH"

# 验证
if "$BIN_PATH" version >/dev/null 2>&1; then
    echo "✅ sing-box v$VERSION 安装成功！"
    "$BIN_PATH" version | head -1
else
    echo "❌ 二进制无法执行"
    exit 1
fi

echo ""
echo "📌 下一步："
echo "   git add bin/sing-box"
echo "   git commit -m 'chore: 升级 sing-box 至 v\$VERSION'"
echo "   git push origin main"
echo "   然后构建 Docker 镜像：sudo docker build -t hedou999/proxy-manager:latest ."