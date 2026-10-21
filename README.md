# EsBDI

在一组已经互通的 Linux 机器上安装一套学习用集群：ZooKeeper、Hadoop 2.7 HA、Spark on YARN、HBase、Kafka 和 Flume。Redis 可选，需要自己提供编译好的压缩包。

这套脚本只适合隔离的实验网络。组件版本已经停止维护，Hadoop 用 `sshfence` 做高可用隔离，Redis 默认没有密码并且监听所有网卡。

## 目录

| 路径 | 作用 |
| --- | --- |
| `config.sh` | 唯一需要修改的参数文件 |
| `install.sh` | 下载、配置、分发，并按顺序启动 |
| `start-all.sh` / `stop-all.sh` | 按依赖顺序启动或停止 |
| `status.sh` | 在每台机器上执行 `jps`，并打印地址 |
| `clean.sh` | 先停止，再删除安装目录、数据目录和临时包 |
| `lib/` | 每个组件一块，公共的 SSH、模板和校验也在这里 |
| `resource/` | Hadoop 和 HBase 的配置模板，Flume 示例 agent |
| `tests/run.sh` | 不连集群的本地检查 |

`bash test.sh` 或 `make test` 会跑这些检查。

## 安装前

准备至少三台机器，主机名例如 `bd01`、`bd02`、`bd03`，并且每台都能解析所有主机名。安装账号要能免密 SSH 到所有节点，包括自己。JDK 路径在每台上都相同。Hadoop 的 `sshfence` 需要各 NameNode 上存在同一路径的 `id_rsa` 或 `id_ed25519`，还需要 `fuser`（`psmisc`）。

```bash
sudo yum install -y wget tar psmisc
```

控制机还需要 `bash` 4.2 或更新版本、`sha512sum`、`ssh-keyscan` 和 `getent`。在 `bd01` 上进入本目录，按自己的机器修改 `config.sh`，然后执行：

```bash
bash install.sh
```

只分发不启动时用 `bash install.sh --no-start`，之后执行 `bash start-all.sh`。

## 默认拓扑

`config.sh` 里的示例是三台机器。NameNode 和 ResourceManager 必须正好两台，JournalNode 至少三台。DataNode 和 NodeManager 使用同一份 `data_node`，因为 Hadoop 2.7 只有一个 `slaves` 文件。

Hadoop、HBase 或 Spark 打开时必须同时打开 ZooKeeper。Kafka 也依赖 ZooKeeper。HBase 的 ZooKeeper 地址只写主机名，端口单独配置。

重复执行 `install.sh` 会覆盖程序和配置，但已经格式化过的 NameNode 不会再次格式化。改节点、改集群名或要清空数据时，先执行 `bash clean.sh`。`clean.sh` 会删除 `install_dir`、`temp_dir` 和 `temp_data_dir`，这三个路径必须是至少两级的绝对路径。

## 端口

| 服务 | 地址 |
| --- | --- |
| HDFS NameNode | `http://<name_node>:50070` |
| YARN ResourceManager | `http://<resource_manager>:8088` |
| MapReduce JobHistory | `http://<jobhistory_node>:19888` |
| Spark History Server | `http://<spark_history_node>:18080` |
| HBase Master | `http://<hbase_node 第一台>:16010` |
| ZooKeeper | `2181` |
| Kafka | `9092` |

Flume 只安装程序、`JAVA_HOME` 和 `conf/esbdi-example.conf`，不会自动启动。示例 agent 只监听本机 `44444`。

## 版本

默认安装包来自 `archive.apache.org`，文件名带有 SHA-512 校验：

- Hadoop 2.7.7
- ZooKeeper 3.4.14
- Spark 2.4.7（Hadoop 2.7 构建）
- HBase 2.2.4
- Kafka 2.4.1
- Flume 1.9.0

这些脚本使用 Hadoop 2 的 `slaves`、`hadoop-daemon.sh` 和 `50070` 端口，不能直接换成 Hadoop 3 的安装包。
