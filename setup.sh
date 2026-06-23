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

# 1. 检查 Python3
if ! command -v python3 &>/dev/null; then
    echo "❌ 需要 Python3，请先安装"
    exit 1
fi

# 2. 创建虚拟环境
if [ ! -d "venv" ]; then
    echo "📦 创建虚拟环境..."
    python3 -m venv venv
fi

source venv/bin/activate

# 3. 安装依赖
echo "📥 安装 Python 依赖..."
pip install -q flask flask-sqlalchemy gunicorn 2>/dev/null

# 4. 创建数据目录
mkdir -p data bin

# 5. 启动服务（后台运行）
echo "🚀 启动 Web 服务（端口 5003）..."
nohup python3 app.py > /tmp/proxy-manager.log 2>&1 &
PID=$!
echo $PID > /tmp/proxy-manager.pid

echo "⏳ 等待服务启动..."
sleep 2

# 6. 自动下载 sing-box 引擎
echo "⬇ 下载 sing-box 引擎..."
curl -s -X POST http://127.0.0.1:5003/api/core/download > /dev/null 2>&1

# 7. 自动启动代理
echo "▶ 启动代理..."
curl -s -X POST http://127.0.0.1:5003/api/core/start > /dev/null 2>&1

# 获取本机 IP
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -z "$IP" ] && IP="<你的IP>"

echo ""
echo "=============================="
echo "  ✅ 部署完成！"
echo "=============================="
echo ""
echo "  🌐 管理界面：http://$IP:5003"
echo ""
echo "  🔒 代理入口："
echo "    SOCKS5  → http://$IP:1080   (浏览器/终端)"
echo "    HTTP    → http://$IP:1081   (Docker 拉镜像)"
echo "    本机    → http://127.0.0.1:1080 / :1081"
echo ""
echo "  ⏹ 停止：  kill \$(cat /tmp/proxy-manager.pid)"
echo "  ▶ 启动：  bash $DIR/setup.sh"
echo ""
echo "=============================="
