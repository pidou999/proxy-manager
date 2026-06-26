#!/usr/bin/env bash
#
# Proxy Manager 开机自启守护脚本
# 由 crontab @reboot 调用，部署到 /etc/profile.d/qwenpaw.sh 后 crontab 会有 PATH
#
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

LOG="/tmp/proxy-manager-boot.log"
PID_FILE="/tmp/proxy-manager.pid"
LOCK_FILE="/tmp/proxy-manager-boot.lock"

# ─── 防止多实例 ──────────────────────────────────────
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "[boot] another instance is running, exit" >> "$LOG"
    exit 0
fi

echo "==== proxy-manager autostart: $(date) ====" >> "$LOG"

# ─── 加载 PATH（crontab 环境通常没 /usr/local/bin 等）───
[ -f /etc/profile ] && . /etc/profile 2>/dev/null || true
[ -f /etc/profile.d/qwenpaw.sh ] && . /etc/profile.d/qwenpaw.sh 2>/dev/null || true
[ -f ~/.bash_profile ] && . ~/.bash_profile 2>/dev/null || true
[ -f ~/.profile ] && . ~/.profile 2>/dev/null || true

# ─── 激活 Python venv（飞牛 OS 默认位置）────────────
QWENPAW_VENV="/var/apps/com.dustinky.qwenpaw/home/venv/bin/activate"
if [ -f "$QWENPAW_VENV" ]; then
    . "$QWENPAW_VENV"
    echo "[boot] using QwenPaw venv" >> "$LOG"
elif [ -d "venv" ]; then
    . venv/bin/activate
    echo "[boot] using local venv" >> "$LOG"
fi

# ─── 等待网络就绪（最多 60 秒）──────────────────────
NETWORK_READY=false
for i in $(seq 1 60); do
    if ping -c 1 -W 2 223.5.5.5 >/dev/null 2>&1 || \
       ping -c 1 -W 2 192.168.31.1 >/dev/null 2>&1; then
        NETWORK_READY=true
        echo "[boot] network ready after ${i}s" >> "$LOG"
        break
    fi
    sleep 1
done
if [ "$NETWORK_READY" = false ]; then
    echo "[boot] network not ready after 60s, continue anyway" >> "$LOG"
fi

# ─── 启动 Web 服务（如果没在运行）───────────────────
is_running() {
    [ -f "$PID_FILE" ] && \
        PID=$(cat "$PID_FILE" 2>/dev/null) && \
        [ -n "$PID" ] && \
        kill -0 "$PID" 2>/dev/null
}

if is_running; then
    echo "[boot] already running PID=$(cat $PID_FILE)" >> "$LOG"
else
    # 清理过期 PID 文件
    rm -f "$PID_FILE"

    # 用 setsid 完全脱离当前会话（避免 cron 退出时杀掉子进程）
    setsid nohup python3 app.py > /tmp/proxy-manager.log 2>&1 < /dev/null &
    NEW_PID=$!
    disown 2>/dev/null || true
    echo "$NEW_PID" > "$PID_FILE"
    echo "[boot] flask started PID=$NEW_PID" >> "$LOG"

    # 等待 Flask 端口就绪（最多 60 秒）
    FLASK_READY=false
    for i in $(seq 1 60); do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://127.0.0.1:5003/api/core/status 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ]; then
            FLASK_READY=true
            echo "[boot] flask ready after ${i}s (HTTP $HTTP_CODE)" >> "$LOG"
            break
        fi
        sleep 1
    done
    if [ "$FLASK_READY" = false ]; then
        echo "[boot] flask not ready after 60s, abort" >> "$LOG"
        exit 1
    fi
fi

# ─── 检查/下载 sing-box 引擎 ─────────────────────────
if [ ! -f "bin/sing-box" ]; then
    echo "[boot] downloading sing-box..." >> "$LOG"
    DL_RESULT=$(curl -s -X POST http://127.0.0.1:5003/api/core/download 2>&1)
    echo "[boot] download result: $DL_RESULT" >> "$LOG"
fi

# ─── 启动代理引擎 ──────────────────────────────────
echo "[boot] starting sing-box..." >> "$LOG"
START_RESULT=$(curl -s -X POST http://127.0.0.1:5003/api/core/start 2>&1)
echo "[boot] start result: $START_RESULT" >> "$LOG"

# ─── 验证引擎是否真起来 ─────────────────────────────
sleep 2
STATUS=$(curl -s http://127.0.0.1:5003/api/core/status 2>/dev/null)
echo "[boot] final status: $STATUS" >> "$LOG"

if echo "$STATUS" | grep -q '"running": true'; then
    echo "[boot] ✅ proxy-manager fully ready" >> "$LOG"
else
    echo "[boot] ⚠️  proxy-manager started but engine not running" >> "$LOG"
fi

echo "==== done ====" >> "$LOG"
exit 0