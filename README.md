# Proxy Manager 🛡️

> 自带代理引擎的多协议代理管理器 — 无需 Docker，一行命令部署

**一键部署，开箱即用。** 支持 VLESS / VMess / Shadowsocks / Trojan / Hysteria2 / Tuic 六种协议。自带 Web 管理界面，分组管理、连接测速、智能路由、全局代理一应俱全。

---

## 📦 快速开始

```bash
git clone https://github.com/你的用户名/proxy-manager.git
cd proxy-manager
bash setup.sh
```

等脚本跑完，浏览器打开 `http://<你的IP>:5003`：

1. 点击 **⬇ 下载引擎** — 自动下载 sing-box 二进制
2. 点击 **➕ 添加** — 粘贴你的代理链接（支持六种协议）
3. 点击 **▶ 启动** — 代理即刻生效

> `setup.sh` 会自动创建 Python 虚拟环境、安装依赖、启动 Web 服务。

---

## 📖 完整使用教程

### 一、添加代理链接

支持六种协议的分享链接格式，直接粘贴即可：

| 协议 | 链接格式示例 |
|------|-------------|
| **VLESS** | `vless://uuid@server:port?security=reality&flow=...` |
| **VMess** | `vmess://base64编码的JSON` |
| **Shadowsocks** | `ss://base64加密方法:密码@server:port` |
| **Trojan** | `trojan://密码@server:port?security=tls` |
| **Hysteria2** | `hysteria2://密码@server:port?insecure=1` |
| **Tuic** | `tuic://uuid@server:port?congestion_control=bbr` |

**操作步骤：**
- 点击工具栏 **➕ 添加** → 粘贴链接 → 选择分组 → 确认
- 也可以点击 **📥 导入**，批量粘贴多行链接，或上传文件

### 二、分组管理

每个分组包含一组代理，方便按用途分类（如：香港节点、美国节点、游戏加速等）。

**操作：**
- **创建分组**：点击 **📁 分组** 输入名称即可
- **重命名/删除**：点击分组右上角 **✏️**
- **拖拽排序**：拖动分组左侧 `☰` 图标，或拖动代理左侧 `⠿` 图标
- **设置默认出口**：点击代理右侧的 ⭐ 星标，该代理将作为分组默认出口

### 三、连接测试

点击任意代理右侧的 **🧪** 按钮，系统会自动测试：

- **TCP 协议**（VLESS、VMess、Shadowsocks、Trojan）：TCP 端口连通性 + 延迟
- **UDP 协议**（Hysteria2、Tuic）：UDP 发包测试 + TCP 443 回退延迟
- **DNS 解析** + **ICMP Ping**

测试结果会显示延迟毫秒数，并自动存入数据库。

**全局测速：** 点击 **🌐 全局测速** 一次性测试所有已启用代理。

### 四、智能路由 🤖

> 自动选择延迟最低的节点，某个节点挂了会自动切换到下一个。

**启用方法：**
1. 先点击 **🌐 全局测速** 让所有代理都有延迟数据
2. 点击分组右上角的 **📡 手动** → 切换为 **🤖 智能**
3. sing-box 会每 3 分钟自动检测一次延迟，自动走最快的节点

**工作原理：**
- 使用 sing-box 原生 `url-test` outbound
- 检测目标：`https://www.gstatic.com/generate_204`
- 间隔：3 分钟
- 容忍度：50ms（延迟差在 50ms 内的节点视为同等速度，减少无谓切换）

### 五、全局代理 🌍

> 一键开启系统级代理，所有终端命令自动走代理。

**操作方法：** 点击工具栏 **🌍 全局代理 · OFF** → 切换为 **🌍 全局代理 · ON**

**开启后生效的环境变量：**

```bash
export http_proxy=http://127.0.0.1:1081
export https_proxy=http://127.0.0.1:1081
export ALL_PROXY=socks5://127.0.0.1:1080
export NO_PROXY=localhost,127.0.0.1,.local,192.168.0.0/16
```

**生效范围：**
- 新打开的终端会话自动加载（写入 `~/.profile`）
- 已打开的终端需要执行 `source ~/.profile` 或重新打开
- 重启后状态保留

### 六、引擎控制

| 功能 | 操作 |
|------|------|
| **下载引擎** | 点击 **⬇ 下载引擎**（仅首次需要） |
| **启动代理** | 点击 **▶ 启动** |
| **停止代理** | 点击 **⏹ 停止** |
| **开机自启** | 点击 **⏻ 开机自启**（绿色 ✅ 即已开启） |

**开机自启原理：** 写入 crontab `@reboot` 条目，系统启动后自动运行 `start-daemon.sh`。

### 七、导入导出

- **📥 导入**：粘贴多行链接，或拖拽文件到上传区域，批量导入
- **📤 导出**：导出全部链接为文本，或选择一个分组导出 sing-box 配置
- 导入时会自动去重（按链接内容对比）

### 八、Docker 使用代理

如果你在 NAS 上跑 Docker 容器，想让容器走代理拉镜像：

```bash
# 在 Docker 配置中设置 HTTP 代理
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=http://192.168.31.239:1081"
Environment="HTTPS_PROXY=http://192.168.31.239:1081"
Environment="NO_PROXY=localhost,127.0.0.1,.local"
EOF
systemctl daemon-reload
systemctl restart docker
```

> 注意：Docker 拉镜像必须用 **HTTP 端口 1081**，不能用 SOCKS5 的 1080。

---

## 🔌 端口速查

| 端口 | 协议 | 用途 | 绑定地址 |
|------|------|------|---------|
| `5003` | HTTP | Web 管理界面 | `0.0.0.0` |
| `1080` | SOCKS5 | 代理入口（浏览器/终端） | `0.0.0.0` |
| `1081` | HTTP/SOCKS 混合 | 代理入口（Docker/HTTP 应用） | `0.0.0.0` |

> 监听 `0.0.0.0` 意味着局域网内所有设备都可以连接。**请仅在可信内网使用。**

### 本机连接

```bash
# SOCKS5
curl -x socks5://127.0.0.1:1080 http://ip.sb

# HTTP
curl -x http://127.0.0.1:1081 http://ip.sb
```

### 局域网其他设备连接

```bash
curl -x http://192.168.31.239:1081 http://ip.sb
```

---

## 📁 项目结构

```
proxy-manager/
├── app.py              # Flask 后端（全部 API + sing-box 管理）
├── setup.sh            # 一键部署脚本
├── start-daemon.sh     # 开机自启守护脚本（直接安装模式）
├── uninstall.sh        # 一键卸载脚本
├── Dockerfile          # Docker 镜像构建
├── docker-compose.yml  # Docker Compose 编排
├── docker-entrypoint.sh # Docker 容器启动脚本
├── requirements.txt    # Python 依赖
├── static/
│   ├── css/style.css   # 样式
│   └── js/app.js       # 前端逻辑
├── templates/
│   └── index.html      # 主页面
├── bin/                # sing-box 引擎目录（运行时下载）
├── data/               # SQLite 数据库（运行时生成）
├── .gitignore
├── LICENSE             # MIT
└── README.md
```

---

## ⚙️ 手动部署

如果你不想用 `setup.sh`，也可以手动操作：

```bash
# 1. 安装 Python 依赖
pip install flask flask-sqlalchemy

# 2. 启动 Web 服务
python3 app.py

# 3. 下载引擎（通过 API 或网页按钮）
curl -X POST http://127.0.0.1:5003/api/core/download

# 4. 启动代理
curl -X POST http://127.0.0.1:5003/api/core/start

# 5. 查看状态
curl -s http://127.0.0.1:5003/api/core/status | python3 -m json.tool
```

---

## 🐳 Docker 部署

适合不想污染宿主机 Python 环境，或者想用容器化管理的用户。

### 前置要求

- Docker 20+
- Docker Compose v2

### 快速开始（推荐用 Docker Hub 镜像）

```bash
# 1. 创建独立的数据/引擎目录（避免污染宿主机）
mkdir -p ~/docker/proxy-manager/{data,bin}

# 2. 拉取镜像
sudo docker pull hedou999/proxy-manager:latest

# 3. 启动容器
sudo docker run -d \
  --name proxy-manager \
  --network host \
  --restart unless-stopped \
  -v ~/docker/proxy-manager/data:/app/data \
  -v ~/docker/proxy-manager/bin:/app/bin \
  hedou999/proxy-manager:latest
```

或者直接用 docker-compose（项目根目录有 `docker-compose.yml`）：

```bash
git clone https://github.com/pidou999/proxy-manager.git
cd proxy-manager
docker compose up -d
```

### 在飞牛/极空间 Docker 面板部署

镜像名：**`hedou999/proxy-manager:latest`**

1. **镜像** → 拉取 → 填 `hedou999/proxy-manager:latest` → 等待拉取完成
2. **容器** → 添加容器：
   - **网络**：必须选 `host`（让 sing-box 直接监听主机端口，局域网设备可直连）
   - **挂载**：
     - 宿主机路径 `/vol1/docker/proxy-manager/data` → 容器路径 `/app/data`
     - 宿主机路径 `/vol1/docker/proxy-manager/bin` → 容器路径 `/app/bin`
   - **重启策略**：`always` 或 `unless-stopped`
3. 启动容器 → 浏览器开 `http://NAS_IP:5003`

### 推荐挂载目录布局

把数据和引擎放在独立目录，**不放在项目目录下**，好处是：
- ✅ 项目目录可以随时 `git pull` 升级，不会冲突
- ✅ 数据目录独立备份/迁移更方便
- ✅ 项目目录删除不会丢数据

```
/vol1/docker/proxy-manager/
├── data/    # SQLite 数据库（代理链接、配置）
└── bin/     # sing-box 二进制 + 运行时配置/日志/PID
```

> ⚠️ 别人 clone 这个项目时**不会**拿到你的代理链接、服务器地址等隐私数据。
> `data/` 和 `bin/` 都不在仓库里，Docker 镜像里也是空的。

### 升级流程

项目升级（比如新增功能或修复 bug）后：

```bash
# 1. 拉取最新代码
cd proxy-manager
git pull origin main

# 2. 停止并删除旧容器（数据在挂载目录里，不会丢）
sudo docker stop proxy-manager
sudo docker rm proxy-manager

# 3. 拉取最新镜像
sudo docker pull hedou999/proxy-manager:latest

# 4. 重新启动
sudo docker run -d \
  --name proxy-manager \
  --network host \
  --restart unless-stopped \
  -v ~/docker/proxy-manager/data:/app/data \
  -v ~/docker/proxy-manager/bin:/app/bin \
  hedou999/proxy-manager:latest
```

或在 Docker 面板：
1. 容器 → 停掉 `proxy-manager`
2. 删除容器
3. 镜像 → 拉取 → 选最新版本
4. 重新创建容器（配置不变）

### 容器内访问

| 服务 | 地址 |
|------|------|
| Web 管理 | `http://localhost:5003` 或 `http://<宿主机IP>:5003` |
| SOCKS5 代理 | `localhost:1080` 或 `<宿主机IP>:1080` |
| HTTP 代理 | `localhost:1081` 或 `<宿主机IP>:1081` |

### 配置文件说明

镜像内 sing-box 二进制预装在 `/usr/local/bin/sing-box`（约 60 MB），容器启动时自动复制到 `/app/bin/sing-box`。**容器内不需要下载**任何东西。

### Docker 模式注意事项

- **开机自启按钮**：Docker 模式下由 `restart: unless-stopped` 控制，Web 按钮显示为常亮状态
- **数据目录**：宿主机 `./data` 和 `./bin` 即持久化目录
- **网络模式**：必须用 `host`，否则 sing-box 监听 1080/1081 在容器内，局域网设备连不上
- **镜像体积**：约 100 MB（含 Python 3.11 + Flask + sing-box）

### 与直接安装的区别

| 功能 | 直接安装 | Docker 安装 |
|------|---------|------------|
| Python 环境 | 需要本机 Python | 容器内自带 |
| 依赖安装 | pip install | 自动构建 |
| sing-box | Web 下载 | 镜像内预装 |
| 开机自启 | crontab @reboot | restart: unless-stopped |
| 局域网访问 | 监听 0.0.0.0 | host 网络模式 |
| 数据持久化 | 本机目录 | 挂载卷 |

### 镜像标签说明

- `hedou999/proxy-manager:latest` — 始终是最新稳定版
- `hedou999/proxy-manager:v1.x.x` — 特定版本（如果有）

---

## 🗑️ 一键卸载

```bash
cd proxy-manager
bash uninstall.sh
```

脚本会自动执行以下操作：

1. **停止 Web 服务** — 终止 Flask 进程
2. **停止代理引擎** — 终止 sing-box 进程
3. **清理 crontab 开机自启** — 移除 `@reboot` 条目
4. **清理全局代理变量** — 删除 `/etc/profile.d/proxy-manager.sh` 和 `~/.profile` 中的代理设置
5. **可选删除项目目录** — 询问是否删除整个项目

> 如果终端当前会话还设置了代理环境变量，卸载后执行：
> ```bash
> unset http_proxy https_proxy ftp_proxy ALL_PROXY
> ```

---

## 🛠️ API 参考

| 方法 | 端点 | 用途 |
|------|------|------|
| GET | `/api/groups` | 获取所有分组及代理 |
| POST | `/api/groups` | 创建分组 |
| PUT | `/api/groups/<id>` | 更新分组（名称、默认出口、路由模式） |
| DELETE | `/api/groups/<id>` | 删除分组 |
| POST | `/api/links` | 添加代理链接 |
| PUT | `/api/links/<id>` | 更新代理 |
| DELETE | `/api/links/<id>` | 删除代理 |
| POST | `/api/links/<id>/test` | 测试单个代理 |
| POST | `/api/links/test-all` | 批量测试所有启用代理 |
| GET | `/api/links/export` | 导出链接文本 |
| POST | `/api/links/import` | 批量导入链接 |
| GET | `/api/core/status` | 引擎运行状态 |
| POST | `/api/core/start` | 启动代理引擎 |
| POST | `/api/core/stop` | 停止代理引擎 |
| GET | `/api/core/config` | 下载当前 sing-box 配置 |
| POST | `/api/core/download` | 下载/更新 sing-box 二进制 |
| GET | `/api/settings/autostart` | 开机自启状态 |
| POST | `/api/settings/autostart` | 设置开机自启 |
| GET | `/api/settings/global-proxy` | 全局代理状态 |
| POST | `/api/settings/global-proxy` | 切换全局代理 |

---

## 🔧 常见问题

### Q: 测速显示 "Timeout" 或连接失败
- 检查代理链接是否有效
- Hysteria2/Tuic 是 UDP 协议，TCP 测速会超时，这是正常的
- 不同的代理节点可能被墙，换一个试试

### Q: 开机自启无法设置
- 确保当前用户有 crontab 权限
- 可以手动添加 `@reboot` 到 crontab

### Q: Docker 拉镜像速度慢
- 确认使用 HTTP 端口 `1081`（SOCKS5 的 1080 对 Docker 支持不佳）
- 参考上方「Docker 使用代理」章节配置

### Q: Global Proxy 开启了但终端不走代理
- 新终端才生效，老终端执行 `source ~/.profile`
- 检查环境变量：`echo $http_proxy`

---

## 🧪 技术栈

- **后端**：Python Flask + SQLAlchemy + SQLite
- **前端**：原生 HTML / CSS / JavaScript
- **代理引擎**：[sing-box](https://github.com/SagerNet/sing-box) v1.13+（Go 语言，单文件静态二进制）
- **开源协议**：MIT

---

## ⚠️ 安全须知

- 管理界面**无密码认证**，默认全开放。**请仅在可信内网使用。**
- 建议通过防火墙限制管理端口 5003 的访问来源
- 代理端口（1080/1081）监听 `0.0.0.0`，局域网内所有设备均可连接

---

## 📄 许可证

MIT License — 随便用，随便改，随便分享。
