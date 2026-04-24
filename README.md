# dst

基于 `debian:bookworm-slim` 和 SteamCMD 的饥荒联机版（Don't Starve Together, DST）专用服务器镜像。

这个仓库已经包含：

- 一套默认世界模板 `Cluster_1`
- 模组订阅文件 `mods/dedicated_server_mods_setup.lua`
- 自动更新、日志轮转、自动备份、双分片启动脚本 `run_dedicated_servers.sh`

容器启动后会自动做这些事：

- 通过 SteamCMD 更新 DST 服务端文件
- 第一次启动时把镜像里的 `Cluster_1` 和 `mods` 复制到数据目录
- 启动 `Master` 和 `Caves` 两个分片
- 轮转日志
- 按天自动做世界备份

## 目录说明

- `Dockerfile`：镜像构建文件
- `run_dedicated_servers.sh`：入口脚本
- `Cluster_1/`：默认世界配置
- `mods/`：默认模组订阅配置

## 本地构建

```bash
docker build -t niudea/dst:latest .
```

## 运行示例

先准备持久化目录：

```bash
mkdir -p runtime/klei runtime/dst
```

然后启动容器：

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

当前仓库默认配置里用到的端口是：

- `10999/udp`：Master 分片
- `10998/udp`：Caves 分片
- `27017/udp`：Caves `master_server_port`
- `8767/udp`：Caves `authentication_port`

如果你改了 `Cluster_1` 里的配置文件，记得同步调整容器端口映射。

## 首次启动行为

- 如果 `/root/.klei/DoNotStarveTogether/Cluster_1` 不存在，容器会把镜像内置的 `Cluster_1` 和 `mods` 复制到挂载目录。
- 如果世界目录已经存在，容器不会覆盖你已有的存档和模组目录。
- 日志默认写到 `/root/.klei/DoNotStarveTogether/logs`。

## 常用环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `DST_CLUSTER_NAME` | `Cluster_1` | 启动的世界目录名 |
| `DST_INSTALL_DIR` | `/root/steam/dst` | DST 服务端安装目录 |
| `DST_DONTSTARVE_DIR` | `/root/.klei/DoNotStarveTogether` | Klei 数据目录 |
| `DST_LOG_DIR` | `/root/.klei/DoNotStarveTogether/logs` | 日志目录 |
| `DST_LOG_MAX_SIZE` | `10M` | 单个日志文件达到这个大小后轮转 |
| `DST_LOG_ROTATE_COUNT` | `3` | 日志保留份数 |
| `DST_LOG_ROTATE_INTERVAL` | `60` | 日志轮转检查间隔，单位秒 |
| `DST_SHUTDOWN_TIMEOUT` | `60` | 收到停止信号后的优雅停机等待时间，单位秒 |
| `DST_AUTOBACKUP_ENABLED` | `1` | 是否开启自动备份 |
| `DST_AUTOBACKUP_INTERVAL_DAYS` | `10` | 每隔多少个游戏天做一次备份 |
| `DST_AUTOBACKUP_MAX_BACKUPS` | `10` | 最多保留多少份自动备份 |
| `DST_AUTOBACKUP_NICE` | `10` | 自动备份进程优先级 |
| `DST_AUTOBACKUP_DIR` | `/root/.klei/DoNotStarveTogether/autobackups/Cluster_1` | 自动备份输出目录 |
| `DST_AUTOBACKUP_ANNOUNCE_START` | `[DST] World backup started.` | 开始备份时的公告 |
| `DST_AUTOBACKUP_ANNOUNCE_END` | `[DST] World backup finished.` | 结束备份时的公告 |

示例：

```bash
docker run -d \
  --name dst \
  --restart unless-stopped \
  -p 10999:10999/udp \
  -p 10998:10998/udp \
  -p 27017:27017/udp \
  -p 8767:8767/udp \
  -e DST_AUTOBACKUP_INTERVAL_DAYS=5 \
  -e DST_AUTOBACKUP_MAX_BACKUPS=20 \
  -v "$PWD/runtime/klei:/root/.klei/DoNotStarveTogether" \
  -v "$PWD/runtime/dst:/root/steam/dst" \
  niudea/dst:latest
```

## Docker Hub 自动推送

仓库已新增 GitHub Actions 工作流 `.github/workflows/dockerhub.yml`，行为如下：

- 触发条件：推送到 `main` 分支，或者手动执行
- 推送标签：`latest` 和当天日期标签
- 日期格式：`YYYYMMDD`
- 当前实现使用 UTC 时间生成日期标签，例如 `20260424`

### 需要配置的 GitHub Secrets

到 GitHub 仓库的 `Settings > Secrets and variables > Actions` 新建：

- `DOCKERHUB_USERNAME`：你的 Docker Hub 用户名
- `DOCKERHUB_TOKEN`：你的 Docker Hub Access Token

工作流默认会把镜像推到：

```text
${DOCKERHUB_USERNAME}/dst:latest
${DOCKERHUB_USERNAME}/dst:YYYYMMDD
```

所以你需要先在 Docker Hub 里创建一个名为 `dst` 的仓库，或者确保你的账号下允许首次推送自动创建对应仓库。

## 注意事项

- 当前仓库带有 `Cluster_1/cluster_token.txt`，公开仓库里不建议长期直接使用，正式开服前建议替换成你自己的 token。
- 当前默认配置里 `Cluster_1/cluster.ini` 的 `cluster_password = 12345`，公开使用前建议改掉。
- `adminlist.txt`、模组配置、世界参数都已经进仓库了，后续如果改动，直接改挂载目录里的持久化文件更稳妥。
