#!/usr/bin/env bash
#
# Proxy Manager — 一键卸载脚本
# 停止服务、清理开机自启、清除全局代理环境变量
#

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "========================================"
echo "  Proxy Manager — 卸载"
echo "========================================"
echo "项目目录: $PROJECT_DIR"
echo ""

# ─── 确认 ──────────────────────────────────
read -r -p "⚠️  确定要卸载 Proxy Manager？(y/N) " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

# ─── 1. 停止 Web 服务 ──────────────────────
echo ""
echo "[1/5] 停止 Web 服务..."
# Kill Flask app
FLASK_PID=$(ps aux | grep "app.py" | grep -v grep | awk '{print $2}')
if [ -n "$FLASK_PID" ]; then
    kill -9 $FLASK_PID 2>/dev/null || true
    echo "  ✅ Flask 进程已终止"
else
    echo "  ⏭️  Flask 未运行"
fi

# ─── 2. 停止 sing-box 引擎 ──────────────────
echo "[2/5] 停止代理引擎..."
if [ -f "$PROJECT_DIR/bin/sing-box.pid" ]; then
    PID=$(cat "$PROJECT_DIR/bin/sing-box.pid" 2>/dev/null || echo "")
    if [ -n "$PID" ]; then
        kill -9 "$PID" 2>/dev/null || true
        echo "  ✅ sing-box 进程($PID)已终止"
    fi
    rm -f "$PROJECT_DIR/bin/sing-box.pid"
else
    # 尝试通过 API 停止
    curl -s -X POST http://127.0.0.1:5003/api/core/stop >/dev/null 2>&1 && echo "  ✅ 已通过 API 停止 sing-box" || echo "  ⏭️  sing-box 未运行"
fi

# ─── 3. 清理 crontab 开机自启 ───────────────
echo "[3/5] 清理 crontab 开机自启..."
if crontab -l 2>/dev/null | grep -q "proxy-manager"; then
    crontab -l 2>/dev/null | grep -v "proxy-manager" | crontab - 2>/dev/null
    echo "  ✅ crontab 开机自启已移除"
else
    echo "  ⏭️  未设置开机自启"
fi

# ─── 4. 清理全局代理环境变量 ────────────────
echo "[4/5] 清理全局代理环境变量..."
# /etc/profile.d/
if [ -f /etc/profile.d/proxy-manager.sh ]; then
    rm -f /etc/profile.d/proxy-manager.sh 2>/dev/null && echo "  ✅ /etc/profile.d/proxy-manager.sh 已删除" || echo "  ⚠️  无法删除 /etc/profile.d/proxy-manager.sh（需要 root）"
fi
# ~/.profile
HOME_DIR="${HOME:-/root}"
if [ -f "$HOME_DIR/.profile" ]; then
    if grep -q "PROXY MANAGER" "$HOME_DIR/.profile" 2>/dev/null; then
        # 用 sed 删除 PROXY MANAGER 段
        sed -i '/# PROXY MANAGER/,/^$/d' "$HOME_DIR/.profile" 2>/dev/null || true
        echo "  ✅ ~/.profile 代理环境变量已清理"
    else
        echo "  ⏭️  ~/.profile 中无代理设置"
    fi
fi
# data/global_proxy 状态文件
if [ -f "$PROJECT_DIR/data/global_proxy" ]; then
    rm -f "$PROJECT_DIR/data/global_proxy"
    echo "  ✅ 全局代理状态文件已删除"
fi

# ─── 5. 删除项目文件 ────────────────────────
echo "[5/5] 删除项目文件..."
read -r -p "  是否删除整个项目目录 ($PROJECT_DIR)？(y/N) " del
if [[ "$del" =~ ^[Yy]$ ]]; then
    cd /
    rm -rf "$PROJECT_DIR"
    echo "  ✅ 项目目录已删除"
else
    echo "  ⏭️  保留项目目录"
fi

echo ""
echo "========================================"
echo "  ✅ 卸载完成"
echo "========================================"
echo ""
echo "提示：如果终端还设置了代理环境变量，执行以下命令清除："
echo "  unset http_proxy https_proxy ftp_proxy ALL_PROXY"
echo ""
