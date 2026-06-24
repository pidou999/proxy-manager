#!/bin/sh
# Proxy Manager Docker 容器启动脚本
# 启动 Flask + 准备 sing-box + 启动代理引擎
set -e

cd /app

# 如果挂载的 bin/ 目录里没有 sing-box，从镜像预装位置复制
if [ ! -f "bin/sing-box" ]; then
    echo "[entrypoint] sing-box not found in bin/, copying from /usr/local/bin/sing-box"
    if [ -f "/usr/local/bin/sing-box" ]; then
        cp /usr/local/bin/sing-box bin/sing-box
        chmod +x bin/sing-box
        echo "[entrypoint] sing-box copied successfully"
    else
        echo "[entrypoint] WARNING: sing-box not found anywhere, will try downloading"
    fi
fi

# 启动 Flask 后台运行
echo "[entrypoint] starting Flask..."
python3 app.py > /tmp/flask.log 2>&1 &
FLASK_PID=$!
echo $FLASK_PID > /tmp/flask.pid

# 等待 Flask ready
for i in $(seq 1 30); do
    if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:5003/api/core/status 2>/dev/null | grep -q 200; then
        echo "[entrypoint] Flask ready"
        break
    fi
    sleep 1
done

# 启动代理引擎（如果 sing-box 已就绪）
if [ -f "bin/sing-box" ]; then
    echo "[entrypoint] starting sing-box..."
    curl -s -X POST http://127.0.0.1:5003/api/core/start > /tmp/start.log 2>&1
    cat /tmp/start.log
else
    echo "[entrypoint] sing-box still missing, please click 下载引擎 in web UI"
fi

# 等待 Flask 退出（前台保持）
wait $FLASK_PID