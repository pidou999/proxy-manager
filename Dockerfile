FROM python:3.11-alpine

WORKDIR /app

# 安装基础工具
RUN apk add --no-cache curl bash

# 安装 Python 依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 预装 sing-box 二进制（直接从宿主机复制，避免 build 时下载）
COPY bin/sing-box /usr/local/bin/sing-box
RUN chmod +x /usr/local/bin/sing-box

# 复制项目文件
COPY app.py docker-entrypoint.sh ./
COPY templates/ ./templates/
COPY static/ ./static/

# 运行目录（预先放入 sing-box，容器内启动引擎时不需要下载）
RUN mkdir -p /app/bin /app/data && \
    cp /usr/local/bin/sing-box /app/bin/sing-box && \
    chmod +x docker-entrypoint.sh

EXPOSE 5003 1080 1081

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["python3", "app.py"]