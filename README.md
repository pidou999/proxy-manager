# Proxy Manager 🛡️

> 自带代理引擎的多协议代理管理器 — 无需 Docker，一行命令部署

**一键部署，开箱即用。** 支持 VLESS / VMess / Shadowsocks / Trojan / Hysteria2 / Tuic 六种协议。

## 快速开始

```bash
git clone https://github.com/你的用户名/proxy-manager.git
cd proxy-manager
bash setup.sh
```

然后浏览器打开 `http://<你的IP>:5003`，点击 **⬇ 下载引擎** → **▶ 启动**，添加你的代理链接即可使用。

## 功能

- ✨ **六种协议** — VLESS / VMess / Shadowsocks / Trojan / Hysteria2 / Tuic
- 🔌 **自带代理引擎** — 基于 sing-box，无需 Docker 或第三方依赖
- 🌐 **Web 管理界面** — 添加、分组、导入导出、测速，都在浏览器里完成
- 📦 **一键部署** — `bash setup.sh` 全自动装好
- 🔒 **代理入口** — SOCKS5 `:1080` + HTTP `:1081`，局域网全开放

## 代理入口

| 协议 | 地址 | 用途 |
|------|------|------|
| SOCKS5 | `http://IP:1080` | 浏览器插件、终端 |
| HTTP | `http://IP:1081` | Docker 拉镜像、HTTP 应用 |
| SOCKS5 (本机) | `http://127.0.0.1:1080` | 宿主机本地 |
| HTTP (本机) | `http://127.0.0.1:1081` | 宿主机本机 |

> 把 `IP` 换成你机器的局域网地址。

## 手动部署

```bash
# 1. 安装依赖
pip install flask flask-sqlalchemy

# 2. 启动
python3 app.py

# 3. 下载引擎（网页上点 下载引擎 按钮，或）
curl -X POST http://127.0.0.1:5003/api/core/download

# 4. 启动代理
curl -X POST http://127.0.0.1:5003/api/core/start
```

## 项目结构

```
proxy-manager/
├── app.py              # Flask 后端（API + 代理管理）
├── setup.sh            # 一键部署脚本
├── requirements.txt    # Python 依赖
├── static/             # 前端样式和脚本
├── templates/          # 前端页面
├── bin/                # sing-box 引擎（运行后自动下载）
└── data/               # SQLite 数据库（运行时生成）
```

## 技术栈

- **后端**：Python Flask + SQLAlchemy + SQLite
- **前端**：原生 HTML / CSS / JavaScript
- **代理引擎**：sing-box（Go 语言，单文件二进制）

## 许可证

MIT
