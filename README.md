# DST Docker

用 Docker 跑 DST 专用服务器。

## 先准备目录和配置

```bash
mkdir -p runtime/klei runtime/dst
```

默认配置都在这两个文件里：

- `defaults/Cluster_1/cluster.ini`
- `defaults/Cluster_1/cluster_token.txt`

要改服务器名字、描述、密码、人数这些，直接改 `cluster.ini`。

第一次启动前改的是 `defaults/Cluster_1/*`；启动过以后，要改 `runtime/klei/Cluster_1/*`，因为容器不会覆盖已有存档目录。

## 构建镜像

```bash
docker build -t niudea/dst:latest .
```

## 直接启动

```bash
docker run -d \
  --name dst \
  --restart unless-stopped \
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

## 端口

- `10999/udp`：Master
- `10998/udp`：Caves
- `27017/udp`：Caves `master_server_port`
- `8767/udp`：Caves `authentication_port`

如果你改了 `defaults/Cluster_1` 里的端口，记得把 `docker run` 里的端口映射一起改掉。
