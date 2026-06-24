#!/usr/bin/env bash
#
# Proxy Manager — 一键部署脚本
# 给新机器用的，自动安装依赖、启动服务、下载引擎
#
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "=============================="
echo "  Proxy Manager 一键部署"
echo "=============================="

# ─── 1. 检测 Python ──────────────────────────────────
PYTHON_CMD=""
if command -v python3 &>/dev/null; then
    PYTHON_CMD=python3
elif command -v python &>/dev/null; then
    PYTHON_CMD=python
else
    echo "❌ 需要 Python3，请先安装"
    exit 1
fi

# ─── 2. 检测/创建虚拟环境 ──────────────────────────────
# 优先使用 QwenPaw 自带的 venv（飞牛 OS）
QWENPAW_VENV="/var/apps/com.dustinky.qwenpaw/home/venv/bin/activate"
if [ -f "$QWENPAW_VENV" ]; then
    echo "✅ 检测到 QwenPaw venv，使用系统虚拟环境"
    source "$QWENPAW_VENV"
elif [ -d "venv" ]; then
    echo "✅ 使用本地 venv"
    source venv/bin/activate
else
    echo "📦 创建本地虚拟环境 venv..."
    $PYTHON_CMD -m venv venv
    source venv/bin/activate
    echo "📥 安装 Python 依赖..."
    pip install -q --upgrade pip
    pip install -q flask flask-sqlalchemy
fi

# 检查依赖是否齐全（飞牛 OS venv 通常已装好 flask）
if ! python -c "import flask, flask_sqlalchemy" 2>/dev/null; then
    echo "📥 安装 Python 依赖（flask, flask-sqlalchemy）..."
    pip install -q flask flask-sqlalchemy
fi

# ─── 3. 创建数据/引擎目录 ──────────────────────────────
mkdir -p data bin

# ─── 4. 启动 Web 服务 ──────────────────────────────────
if [ -f /tmp/proxy-manager.pid ] && kill -0 $(cat /tmp/proxy-manager.pid) 2>/dev/null; then
    echo "⏭️  服务已在运行 (PID=$(cat /tmp/proxy-manager.pid))"
else
    echo "🚀 启动 Web 服务（端口 5003）..."
    nohup python app.py > /tmp/proxy-manager.log 2>&1 &
    echo $! > /tmp/proxy-manager.pid
    echo "   PID=$(cat /tmp/proxy-manager.pid)"

    # 等待 Flask 就绪（最多 30 秒）
    echo -n "⏳ 等待 Flask 启动"
    for i in $(seq 1 30); do
        if curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://127.0.0.1:5003/api/core/status 2>/dev/null | grep -q 200; then
            echo " ✅"
            break
        fi
        echo -n "."
        sleep 1
    done
fi

# ─── 5. 下载 sing-box 引擎 ──────────────────────────────
echo "⬇ 检查 sing-box 引擎..."
if curl -s http://127.0.0.1:5003/api/core/status | grep -q '"binary_exists": true'; then
    echo "✅ sing-box 已存在"
else
    echo "⬇ 下载 sing-box..."
    RESULT=$(curl -s -X POST http://127.0.0.1:5003/api/core/download)
    if echo "$RESULT" | grep -q '"error"'; then
        echo "⚠️  下载失败，请检查网络（GitHub 访问不通畅时需要代理）"
        echo "    $RESULT"
        echo "    提示：在 Web 界面手动点「⬇ 下载引擎」按钮可重试"
    else
        echo "✅ sing-box 下载完成"
    fi
fi

# ─── 6. 启动代理引擎 ──────────────────────────────────
echo "▶ 启动代理..."
RESULT=$(curl -s -X POST http://127.0.0.1:5003/api/core/start)
if echo "$RESULT" | grep -q '"error"'; then
    echo "⚠️  启动失败：$RESULT"
else
    echo "✅ 代理已启动"
fi

# ─── 7. 输出访问信息 ──────────────────────────────────
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -z "$IP" ] && IP="<你的IP>"

echo ""
echo "=============================="
echo "  ✅ 部署完成！"
echo "=============================="
echo ""
echo "  🌐 管理界面：http://$IP:5003"
echo ""
echo "  🔌 代理入口："
echo "    SOCKS5  → socks5://$IP:1080   (浏览器/终端)"
echo "    HTTP    → http://$IP:1081   (Docker 拉镜像)"
echo "    本机    → 127.0.0.1:1080 / :1081"
echo ""
echo "  ⏹ 停止：  kill \$(cat /tmp/proxy-manager.pid)"
echo "  ▶ 启动：  bash $DIR/setup.sh"
echo "  🗑 卸载：  bash $DIR/uninstall.sh"
echo ""
echo "  📋 日志：tail -f /tmp/proxy-manager.log"
echo ""
echo "=============================="