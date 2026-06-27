#!/usr/bin/env bash
#
# Proxy Manager — Docker 一键部署脚本（带镜像加速器）
# 自动配置国内 Docker 镜像加速器 + 拉取 + 启动容器
#
set -e

IMAGE_NAME="hedou999/proxy-manager:latest"
CONTAINER_NAME="proxy-manager"

echo "=============================="
echo "  Proxy Manager — Docker 部署"
echo "=============================="
echo ""

# ─── 1. 检测 Docker ──────────────────────────────────
if ! command -v docker &>/dev/null; then
    echo "❌ 未检测到 docker，请先安装 Docker"
    exit 1
fi

# 检测 Docker daemon 是否可访问
if ! docker info >/dev/null 2>&1; then
    if command -v sudo &>/dev/null; then
        echo "⚠️  docker 需要 sudo 权限"
        SUDO="sudo"
    else
        echo "❌ 无法访问 Docker daemon"
        exit 1
    fi
else
    SUDO=""
fi

# ─── 2. 配置 Docker 镜像加速器（国内用户）─────────────
echo "🔧 配置 Docker 镜像加速器..."

DAEMON_JSON="/etc/docker/daemon.json"
MIRRORS_CONFIGURED=false

# 检测是否在国内（粗略判断：时区 + 是否有中国相关网络特征）
CN_DETECTED=false
if [ -f /etc/localtime ]; then
    if readlink /etc/localtime 2>/dev/null | grep -qiE "Shanghai|Chongqing|Hong_Kong|Taipei"; then
        CN_DETECTED=true
    fi
fi
# 也可以让用户自己选择
if [ "$CN_DETECTED" = true ]; then
    echo "🇨🇳 检测到中国时区，自动配置国内镜像加速器"
else
    echo "❓ 检测不到时区，是否在中国/网络环境受限？(y/N)"
    read -r cn_answer
    if [[ "$cn_answer" =~ ^[Yy]$ ]]; then
        CN_DETECTED=true
    fi
fi

if [ "$CN_DETECTED" = true ]; then
    # 备份现有配置
    if [ -f "$DAEMON_JSON" ]; then
        cp "$DAEMON_JSON" "$DAEMON_JSON.bak.$(date +%s)" 2>/dev/null || true
    fi

    # 写入镜像加速器
    $SUDO mkdir -p /etc/docker
    $SUDO tee "$DAEMON_JSON" >/dev/null <<'EOF'
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://dockerproxy.com",
    "https://docker.m.daocloud.io"
  ]
}
EOF
    echo "✅ 已配置镜像加速器: $DAEMON_JSON"

    # 重启 Docker daemon
    if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
        $SUDO systemctl restart docker
        echo "✅ 已重启 Docker daemon"
    else
        echo "⚠️  非 systemd 系统，请手动重启 Docker daemon"
    fi
    MIRRORS_CONFIGURED=true
fi

# ─── 3. 创建数据/引擎目录 ──────────────────────────────
DATA_DIR="$HOME/docker/proxy-manager"
mkdir -p "$DATA_DIR/data" "$DATA_DIR/bin"
echo "✅ 数据目录: $DATA_DIR"

# ─── 4. 拉取镜像 ─────────────────────────────────────
echo "📥 拉取镜像 $IMAGE_NAME ..."
if $SUDO docker pull "$IMAGE_NAME" 2>&1 | tail -5; then
    echo "✅ 镜像拉取成功"
else
    echo "❌ 镜像拉取失败，请检查网络或手动: docker pull $IMAGE_NAME"
    exit 1
fi

# ─── 5. 停止旧容器（如有）─────────────────────────────
if $SUDO docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
    echo "🛑 停止旧容器 $CONTAINER_NAME ..."
    $SUDO docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    $SUDO docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
fi

# ─── 6. 启动容器 ─────────────────────────────────────
echo "🚀 启动容器 $CONTAINER_NAME ..."
$SUDO docker run -d \
    --name "$CONTAINER_NAME" \
    --network host \
    --restart unless-stopped \
    -v "$DATA_DIR/data:/app/data" \
    -v "$DATA_DIR/bin:/app/bin" \
    "$IMAGE_NAME"

# ─── 7. 等待启动 ─────────────────────────────────────
echo "⏳ 等待服务启动..."
for i in $(seq 1 30); do
    if curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://127.0.0.1:5003/ 2>/dev/null | grep -q 200; then
        echo "✅ Web 服务已就绪"
        break
    fi
    sleep 1
done

# ─── 8. 输出结果 ─────────────────────────────────────
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
echo "    SOCKS5  → socks5://$IP:1080"
echo "    HTTP    → http://$IP:1081"
echo ""
echo "  📋 常用命令："
echo "    查看日志：$SUDO docker logs -f $CONTAINER_NAME"
echo "    停止容器：$SUDO docker stop $CONTAINER_NAME"
echo "    启动容器：$SUDO docker start $CONTAINER_NAME"
echo "    更新镜像：$SUDO docker pull $IMAGE_NAME && $SUDO docker restart $CONTAINER_NAME"
echo "    卸载：bash uninstall.sh"
echo ""
echo "=============================="