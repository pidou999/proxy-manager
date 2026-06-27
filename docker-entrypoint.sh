#!/bin/sh
# Proxy Manager Docker 容器启动脚本
# 启动 Flask + 准备 sing-box + 启动代理引擎
set -e

cd /app

# ─── 1. 准备 sing-box ─────────────────────────────
# 优先级：
#   1. /app/bin/sing-box （挂载到宿主机的，持久化的，用户自己放进去的）
#   2. /usr/local/bin/sing-box （镜像预装的，Docker build 时 COPY 进去的）
# 找到后都软链接到 /usr/local/bin/sing-box（app.py 的 fallback 路径）

mkdir -p bin
chmod 755 bin 2>/dev/null || true

if [ ! -f "bin/sing-box" ]; then
    if [ -f "/usr/local/bin/sing-box" ]; then
        echo "[entrypoint] copying sing-box from image to bin/"
        cp /usr/local/bin/sing-box bin/sing-box 2>&1 || {
            echo "[entrypoint] copy to bin/ failed, will try direct use of /usr/local/bin/sing-box"
            ln -sf /usr/local/bin/sing-box bin/sing-box 2>/dev/null || true
        }
        chmod +x bin/sing-box 2>/dev/null || true
    else
        echo "[entrypoint] WARNING: sing-box not in image, web UI can download it"
    fi
fi

# 最终验证
if [ -f "bin/sing-box" ]; then
    echo "[entrypoint] ✅ sing-box ready: $(bin/sing-box version 2>&1 | head -1)"
else
    echo "[entrypoint] ⚠️  sing-box not available, please click 下载引擎 in web UI"
fi

# ─── 2. 启动 Flask ─────────────────────────────────
echo "[entrypoint] starting Flask..."
python3 app.py > /tmp/flask.log 2>&1 &
FLASK_PID=$!
echo $FLASK_PID > /tmp/flask.pid

# 等待 Flask 就绪
for i in $(seq 1 30); do
    if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:5003/api/core/status 2>/dev/null | grep -q 200; then
        echo "[entrypoint] Flask ready"
        break
    fi
    sleep 1
done

# ─── 3. 启动代理引擎 ─────────────────────────────
if [ -f "bin/sing-box" ]; then
    echo "[entrypoint] starting sing-box..."
    curl -s -X POST http://127.0.0.1:5003/api/core/start > /tmp/start.log 2>&1
    cat /tmp/start.log
    sleep 2
    STATUS=$(curl -s http://127.0.0.1:5003/api/core/status 2>/dev/null || echo "{}")
    echo "[entrypoint] status: $STATUS"
else
    echo "[entrypoint] sing-box missing, skipping auto-start"
fi

# 等待 Flask 退出（前台保持）
wait $FLASK_PID