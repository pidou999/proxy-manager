#!/bin/sh
# Proxy Manager Docker 容器启动脚本
# 启动 Flask 后，自动下载 sing-box 并启动代理引擎
set -e

cd /app

# 启动 Flask 后台运行
echo "[entrypoint] starting Flask..."
python3 app.py > /tmp/flask.log 2>&1 &
FLASK_PID=$!
echo $FLASK_PID > /tmp/flask.pid

# 等待 Flask ready
for i in {1..30}; do
    if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:5003/api/core/status | grep -q 200; then
        echo "[entrypoint] Flask ready"
        break
    fi
    sleep 1
done

# 下载 sing-box（如果还没有）
if [ ! -f "bin/sing-box" ]; then
    echo "[entrypoint] downloading sing-box..."
    curl -s -X POST http://127.0.0.1:5003/api/core/download > /tmp/download.log 2>&1
fi

# 启动代理引擎
echo "[entrypoint] starting sing-box..."
curl -s -X POST http://127.0.0.1:5003/api/core/start > /tmp/start.log 2>&1

# 等待 Flask 退出（前台保持）
wait $FLASK_PID