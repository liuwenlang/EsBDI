#!/usr/bin/env bash
# 集群参数。只改这个文件，安装逻辑在 lib/ 里。
# 用法、端口和限制见 README.md。

# 组件开关。Hadoop、HBase、Spark、Kafka 会在检查阶段要求它们依赖的组件也打开。
hadoop_install="true"
zookeeper_install="true"
spark_install="true"
hbase_install="true"
kafka_install="true"
# Flume 只分发程序、JAVA_HOME 和一份示例 agent，不会自动启动。
flume_install="true"
# Redis 需要已经编译好的压缩包，默认不装。
redis_install="false"

# 安装结束后是否启动。install.sh --no-start 可以临时关掉。
start_services="true"

# 运行 install.sh 的这台机器，必须能免密 SSH 到所有节点，包括自己。
this_node="bd01"
linux_user_name="hadoop"
# 每台机器上的 JDK 都必须是这个路径。
java_path="/opt/jdk"

# 下面三个目录会在清理时整目录删除，必须是至少两级的绝对路径。
# 写 ~/... 时，波浪号在这台安装机上展开。各节点的家目录需要一致。
temp_dir=~/package
temp_data_dir=~/bdData
install_dir=~/apps

# 支持 http(s) URL 或本机绝对路径。已知文件名会校验 SHA-512。
hadoop_address="https://archive.apache.org/dist/hadoop/common/hadoop-2.7.7/hadoop-2.7.7.tar.gz"
zookeeper_address="https://archive.apache.org/dist/zookeeper/zookeeper-3.4.14/zookeeper-3.4.14.tar.gz"
spark_address="https://archive.apache.org/dist/spark/spark-2.4.7/spark-2.4.7-bin-hadoop2.7.tgz"
hbase_address="https://archive.apache.org/dist/hbase/2.2.4/hbase-2.2.4-bin.tar.gz"
kafka_address="https://archive.apache.org/dist/kafka/2.4.1/kafka_2.11-2.4.1.tgz"
flume_address="https://archive.apache.org/dist/flume/1.9.0/apache-flume-1.9.0-bin.tar.gz"
redis_address="/home/hadoop/package/redis.tar.gz"

# Hadoop 2.7 的 slaves 同时决定 DataNode 和 NodeManager，所以二者使用同一份列表。
hadoop_all_node=("bd01" "bd02" "bd03")
journal_node=("bd01" "bd02" "bd03")
name_node=("bd01" "bd02")
resource_manager=("bd01" "bd02")
data_node=("bd01" "bd02" "bd03")
zookeeper_node=("bd01" "bd02" "bd03")
hbase_node=("bd01" "bd02" "bd03")
kafka_node=("bd01" "bd02" "bd03")
flume_node=("bd01" "bd02" "bd03")
redis_node=("bd01" "bd02" "bd03")

# 留空则使用 this_node。JobHistory 必须属于 hadoop_all_node。
jobhistory_node=""
spark_history_node=""

cluster_name="mycluster"
rm_cluster_id="yrc"
mr_framework="yarn"
bak_num=2

zookeeper_data_dir=${temp_data_dir}/zookeeper
hadoop_workspace=${temp_data_dir}/hadoopdata

http_namenode_port=50070
rpc_namenode_port=8020
journal_node_port=8485
zookeeper_port=2181
zookeeper_in_port=2888
zookeeper_leader_port=3888
jobhistory_service_port=10020
jobhistory_webapp_port=19888
yarn_webapp_port=8088
hbase_web_port=16010

spark_history_ui_port=18080
spark_history_fs_logDirectory=/spark/logs
spark_eventLog_dir=/spark/logs
spark_yarn_archive=/spark/libs

hbase_rootdir="hdfs://${cluster_name}/hbase"

kafka_port=9092
kafka_logs=${temp_data_dir}/kafka

redis_ports=(6379 6380)
redis_cluster_replicas=1
redis_cluster_conf_dir=${temp_data_dir}/redis
# 非空时用这条命令代替自动生成的 redis-cli --cluster create。
redis_create_command=""
