# DST Docker

用 Docker 跑 DST 专用服务器。

## 用 compose 跑

先准备配置和数据目录：

```bash
cp .env.example .env
mkdir -p runtime/klei runtime/dst
```

把 `.env` 里的 `DST_CLUSTER_TOKEN` 改成你自己的 Klei token，需要的话再改服务器名字、密码和人数。

启动：

```bash
docker compose up -d --build
```

看日志：

```bash
docker compose logs -f
```

停止：

```bash
docker compose down
```

## 不用 compose 直接跑

```bash
docker run -d \
  --name dst \
  --restart unless-stopped \
  -p 10999:10999/udp \
  -p 10998:10998/udp \
  -p 27017:27017/udp \
  -p 8767:8767/udp \
  -e DST_CLUSTER_TOKEN=your_klei_cluster_token \
  -v "$PWD/runtime/klei:/root/.klei/DoNotStarveTogether" \
  -v "$PWD/runtime/dst:/root/steam/dst" \
  niudea/dst:latest
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

如果你改了 `defaults/Cluster_1` 里的端口，记得把 `compose.yaml` 里的端口映射一起改掉。
