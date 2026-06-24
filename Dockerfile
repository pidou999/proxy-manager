FROM python:3.11-alpine

WORKDIR /app

# 安装基础工具（curl 用于检测 Flask 是否就绪）
RUN apk add --no-cache curl bash

# 安装 Python 依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 复制项目文件
COPY app.py docker-entrypoint.sh ./
COPY templates/ ./templates/
COPY static/ ./static/

# 运行目录
RUN mkdir -p /app/bin /app/data && chmod +x docker-entrypoint.sh

EXPOSE 5003 1080 1081

# entrypoint 自动启动 Flask + 下载 sing-box + 启动代理
ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["python3", "app.py"]