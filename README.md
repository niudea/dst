# DST Docker

用 Docker 跑 DST 专用服务器。

## 先准备目录和配置

```bash
cp .env.example .env
mkdir -p runtime/klei runtime/dst
```

把 `.env` 里的 `DST_CLUSTER_TOKEN` 改成你自己的 Klei token，需要的话再改服务器名字、密码和人数。

## 构建镜像

```bash
docker build -t niudea/dst:latest .
```

## 直接启动

```bash
docker run -d \
  --name dst \
  --restart unless-stopped \
  --env-file .env \
  -p 10999:10999/udp \
  -p 10998:10998/udp \
  -p 27017:27017/udp \
  -p 8767:8767/udp \
  -v "$PWD/runtime/klei:/root/.klei/DoNotStarveTogether" \
  -v "$PWD/runtime/dst:/root/steam/dst" \
  niudea/dst:latest
```

## 看日志

```bash
docker logs -f dst
```

## 停止并删除容器

```bash
docker rm -f dst
```

## 常用变量

- `DST_CLUSTER_TOKEN`：必填
- `DST_CLUSTER_DISPLAY_NAME`：服务器名字
- `DST_CLUSTER_DESCRIPTION`：服务器描述
- `DST_CLUSTER_PASSWORD`：服务器密码
- `DST_MAX_PLAYERS`：最大人数
- `DST_AUTOBACKUP_INTERVAL_DAYS`：自动备份间隔
- `DST_AUTOBACKUP_MAX_BACKUPS`：备份保留数量

## 端口

- `10999/udp`：Master
- `10998/udp`：Caves
- `27017/udp`：Caves `master_server_port`
- `8767/udp`：Caves `authentication_port`

如果你改了 `defaults/Cluster_1` 里的端口，记得把 `docker run` 里的端口映射一起改掉。
