#!/usr/bin/env bash
# Proxy Manager 开机自启脚本
# 被 crontab @reboot 调用
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

LOG="/tmp/proxy-manager-boot.log"
PID_FILE="/tmp/proxy-manager.pid"
echo "==== proxy-manager autostart: $(date) ====" >> "$LOG"

# 等待网络就绪（最多等 60 秒）
NETWORK_READY=false
for i in {1..60}; do
    # 尝试 ping 外网 DNS 和网关
    if ping -c 1 -W 2 223.5.5.5 >/dev/null 2>&1 || \
       ping -c 1 -W 2 192.168.31.1 >/dev/null 2>&1; then
        NETWORK_READY=true
        break
    fi
    sleep 1
done
if [ "$NETWORK_READY" = true ]; then
    echo "[boot] network ready after ${i}s" >> "$LOG"
else
    echo "[boot] network not ready after 60s, continue anyway" >> "$LOG"
fi

# 启动 Web 服务（如果没在运行）
if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
    echo "[boot] proxy-manager already running PID=$(cat $PID_FILE)" >> "$LOG"
else
    # 用 setsid 让 Flask 完全脱离当前会话
    setsid nohup python3 app.py > /tmp/proxy-manager.log 2>&1 < /dev/null &
    NEW_PID=$!
    disown
    echo $NEW_PID > "$PID_FILE"
    echo "[boot] flask started PID=$NEW_PID" >> "$LOG"
    # 等待 Flask 端口就绪
    for i in {1..30}; do
        curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:5003/api/core/status 2>/dev/null | grep -q 200 && break
        sleep 1
    done
    echo "[boot] flask ready after ${i}s" >> "$LOG"
fi

# 检查引擎是否已下载
if [ ! -f "bin/sing-box" ]; then
    echo "[boot] downloading sing-box..." >> "$LOG"
    curl -s -X POST http://127.0.0.1:5003/api/core/download >> "$LOG" 2>&1
fi

# 启动代理引擎
echo "[boot] starting sing-box..." >> "$LOG"
curl -s -X POST http://127.0.0.1:5003/api/core/start >> "$LOG" 2>&1
echo "==== done ====" >> "$LOG"
exit 0