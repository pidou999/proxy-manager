#!/usr/bin/env bash
# Proxy Manager 开机自启脚本
# 被 crontab @reboot 调用
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# 启动 Web 服务（如果没在运行）
PID_FILE="/tmp/proxy-manager.pid"
if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
    echo "proxy-manager already running"
else
    nohup python3 app.py > /tmp/proxy-manager.log 2>&1 &
    echo $! > "$PID_FILE"
    sleep 2
fi

# 检查引擎是否已下载
if [ ! -f "bin/sing-box" ]; then
    curl -s -X POST http://127.0.0.1:5003/api/core/download > /dev/null 2>&1
fi

# 启动代理引擎
curl -s -X POST http://127.0.0.1:5003/api/core/start > /dev/null 2>&1
