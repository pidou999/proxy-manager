#!/usr/bin/env bash
#
# Proxy Manager — 一键卸载脚本
# 停止服务、清理开机自启、清除全局代理环境变量（可选删项目目录）
#

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="${HOME:-/root}"

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

echo ""

# ─── 1. 停止 Web 服务（Flask）─────────────────────
echo "[1/6] 停止 Web 服务..."

# 用 PID 文件 + 进程命令双重确认，避免误杀其他 Python 进程
PID_FILE="/tmp/proxy-manager.pid"
FLASK_KILLED=false

# 路径 1：PID 文件
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        # 确认是 proxy-manager 的进程
        if grep -q "proxy-manager" "/proc/$PID/cmdline" 2>/dev/null || \
           grep -q "proxy-manager/app.py" "/proc/$PID/comm" 2>/dev/null; then
            kill -9 "$PID" 2>/dev/null || true
            sleep 1
            kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null || true
            echo "  ✅ Flask 进程($PID)已终止"
            FLASK_KILLED=true
        fi
    fi
    rm -f "$PID_FILE"
fi

# 路径 2：兜底用进程名查找
if [ "$FLASK_KILLED" = false ]; then
    PIDS=$(pgrep -f "proxy-manager/app.py" 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        for PID in $PIDS; do
            kill -9 "$PID" 2>/dev/null || true
            echo "  ✅ Flask 进程($PID)已终止"
        done
        FLASK_KILLED=true
    fi
fi

if [ "$FLASK_KILLED" = false ]; then
    echo "  ⏭️  Flask 未运行"
fi

# ─── 2. 停止 sing-box 引擎 ──────────────────
echo "[2/6] 停止代理引擎..."

SINGBOX_KILLED=false

# 路径 1：PID 文件
SINGBOX_PID_FILE="$PROJECT_DIR/bin/sing-box.pid"
if [ -f "$SINGBOX_PID_FILE" ]; then
    PID=$(cat "$SINGBOX_PID_FILE" 2>/dev/null || echo "")
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill -9 "$PID" 2>/dev/null || true
        sleep 1
        kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null || true
        echo "  ✅ sing-box 进程($PID)已终止"
        SINGBOX_KILLED=true
    fi
    rm -f "$SINGBOX_PID_FILE"
fi

# 路径 2：进程名查找
if [ "$SINGBOX_KILLED" = false ]; then
    PIDS=$(pgrep -f "bin/sing-box" 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        for PID in $PIDS; do
            kill -9 "$PID" 2>/dev/null || true
            echo "  ✅ sing-box 进程($PID)已终止"
        done
        SINGBOX_KILLED=true
    fi
fi

# 路径 3：通过 API 停止
if [ "$SINGBOX_KILLED" = false ] && curl -s -o /dev/null --max-time 2 http://127.0.0.1:5003/ 2>/dev/null; then
    if curl -s -X POST --max-time 5 http://127.0.0.1:5003/api/core/stop | grep -q "Stopped"; then
        echo "  ✅ 已通过 API 停止 sing-box"
        SINGBOX_KILLED=true
    fi
fi

if [ "$SINGBOX_KILLED" = false ]; then
    echo "  ⏭️  sing-box 未运行"
fi

# ─── 3. 清理 crontab 开机自启 ───────────────
echo "[3/6] 清理 crontab 开机自启..."

if command -v crontab >/dev/null 2>&1; then
    if crontab -l 2>/dev/null | grep -q "proxy-manager"; then
        # 备份
        crontab -l 2>/dev/null > /tmp/crontab.bak.$(date +%s) || true
        # 移除 proxy-manager 相关条目
        crontab -l 2>/dev/null | grep -v "proxy-manager" | crontab - 2>/dev/null || {
            echo "  ⚠️  crontab 清理失败，可能需要 root 权限"
            exit 1
        }
        # 验证
        if crontab -l 2>/dev/null | grep -q "proxy-manager"; then
            echo "  ⚠️  crontab 清理失败，请手动执行: crontab -e"
        else
            echo "  ✅ crontab 开机自启已移除（备份在 /tmp/crontab.bak.*）"
        fi
    else
        echo "  ⏭️  未设置开机自启"
    fi
else
    echo "  ⏭️  crontab 命令不可用"
fi

# ─── 4. 清理全局代理环境变量 ────────────────
echo "[4/6] 清理全局代理环境变量..."

GLOBAL_CLEANED=false

# /etc/profile.d/proxy-manager.sh
if [ -f /etc/profile.d/proxy-manager.sh ]; then
    if rm -f /etc/profile.d/proxy-manager.sh 2>/dev/null; then
        echo "  ✅ /etc/profile.d/proxy-manager.sh 已删除"
        GLOBAL_CLEANED=true
    else
        echo "  ⚠️  无法删除 /etc/profile.d/proxy-manager.sh（需要 root）"
    fi
fi

# ~/.profile 中的 PROXY MANAGER 段
if [ -f "$HOME_DIR/.profile" ]; then
    if grep -q "PROXY MANAGER" "$HOME_DIR/.profile" 2>/dev/null; then
        # 备份
        cp "$HOME_DIR/.profile" "$HOME_DIR/.profile.bak.$(date +%s)" 2>/dev/null || true
        # 删除 PROXY MANAGER 段（# PROXY MANAGER 开头的注释一直到下一个空行）
        sed -i '/# PROXY MANAGER/,/^$/d' "$HOME_DIR/.profile" 2>/dev/null || true
        if grep -q "PROXY MANAGER" "$HOME_DIR/.profile" 2>/dev/null; then
            echo "  ⚠️  ~/.profile 清理失败，请手动编辑"
        else
            echo "  ✅ ~/.profile 代理环境变量已清理"
            GLOBAL_CLEANED=true
        fi
    fi
fi

# /etc/environment（飞牛 OS 有时也写在这里）
if [ -f /etc/environment ] && grep -q "proxy-manager\|http_proxy" /etc/environment 2>/dev/null; then
    if grep -q "PROXY MANAGER" /etc/environment 2>/dev/null; then
        cp /etc/environment /etc/environment.bak.$(date +%s) 2>/dev/null || true
        sed -i '/# PROXY MANAGER/,/^$/d' /etc/environment 2>/dev/null || true
        echo "  ✅ /etc/environment 代理环境变量已清理"
    fi
fi

# data/global_proxy 状态文件
if [ -f "$PROJECT_DIR/data/global_proxy" ]; then
    rm -f "$PROJECT_DIR/data/global_proxy"
    echo "  ✅ 全局代理状态文件已删除"
fi

# 当前 shell 的环境变量（仅提示）
if [ -n "$http_proxy" ] || [ -n "$https_proxy" ] || [ -n "$all_proxy" ]; then
    echo "  ⚠️  当前 shell 仍有代理环境变量，需手动 unset:"
    echo "      unset http_proxy https_proxy ftp_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY"
fi

if [ "$GLOBAL_CLEANED" = false ] && [ ! -f "$PROJECT_DIR/data/global_proxy" ]; then
    echo "  ⏭️  未设置全局代理"
fi

# ─── 5. 清理 Docker 容器（如果存在） ──────────
echo "[5/6] 清理 Docker 容器..."

if command -v docker >/dev/null 2>&1; then
    # 优先用 sudo（容器可能在 docker 组）
    DOCKER_CMD="docker"
    if ! docker ps >/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
    fi

    # 检查是否有名为 proxy-manager 的容器
    if $DOCKER_CMD ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^proxy-manager$"; then
        read -r -p "  发现 Docker 容器 'proxy-manager'，是否删除？(y/N) " del_docker
        if [[ "$del_docker" =~ ^[Yy]$ ]]; then
            $DOCKER_CMD stop proxy-manager 2>/dev/null || true
            $DOCKER_CMD rm proxy-manager 2>/dev/null || true
            echo "  ✅ Docker 容器已删除"
        else
            echo "  ⏭️  保留 Docker 容器"
        fi
    else
        echo "  ⏭️  未发现 Docker 容器"
    fi
else
    echo "  ⏭️  docker 命令不可用"
fi

# ─── 6. 删除项目文件（可选）───────────────────────
echo "[6/6] 处理项目文件..."

# venv 单独提示
if [ -d "$PROJECT_DIR/venv" ]; then
    read -r -p "  是否同时删除 venv（Python 虚拟环境，约 50 MB）？(y/N) " del_venv
    if [[ "$del_venv" =~ ^[Yy]$ ]]; then
        rm -rf "$PROJECT_DIR/venv"
        echo "  ✅ venv 已删除"
    fi
fi

read -r -p "  是否删除整个项目目录 ($PROJECT_DIR)？(y/N) " del_all
if [[ "$del_all" =~ ^[Yy]$ ]]; then
    cd /
    rm -rf "$PROJECT_DIR"
    echo "  ✅ 项目目录已删除"
else
    echo "  ⏭️  保留项目目录"
    echo ""
    echo "  📋 已清理：Flask进程、sing-box进程、crontab、全局代理环境变量"
    echo "  📦 数据保留在: $PROJECT_DIR/data/ （你的代理链接和配置）"
fi

echo ""
echo "========================================"
echo "  ✅ 卸载完成"
echo "========================================"
echo ""
echo "提示："
echo "  - 当前终端代理环境变量需手动 unset（见上方）"
echo "  - 重新安装: bash setup.sh"
echo ""