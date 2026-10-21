#!/usr/bin/env bash

validate_config() {
  local node port path hosts=()

  : "${start_services:=true}"
  if [[ -z "${jobhistory_node}" ]]; then
    jobhistory_node=${name_node[0]:-}
  fi
  if [[ -z "${spark_history_node}" ]]; then
    spark_history_node=${this_node}
  fi
  : "${kafka_port:=9092}"
  : "${redis_cluster_replicas:=1}"
  : "${yarn_webapp_port:=8088}"
  : "${hbase_web_port:=16010}"

  hadoop_workspace=${hadoop_workspace%/}
  zookeeper_data_dir=${zookeeper_data_dir%/}
  kafka_logs=${kafka_logs%/}
  redis_cluster_conf_dir=${redis_cluster_conf_dir%/}
  install_dir=${install_dir%/}
  temp_dir=${temp_dir%/}
  temp_data_dir=${temp_data_dir%/}
  java_path=${java_path%/}

  [[ -n "${this_node}" ]] || die "this_node is empty"
  [[ -n "${linux_user_name}" ]] || die "linux_user_name is empty"
  [[ "${linux_user_name}" =~ ^[A-Za-z0-9._-]+$ ]] || die "linux_user_name contains unsupported characters"
  valid_host "${this_node}" || die "this_node is not a hostname or IPv4 address: ${this_node}"
  [[ "${cluster_name}" =~ ^[A-Za-z][A-Za-z0-9._-]*$ ]] || die "cluster_name must start with a letter: ${cluster_name}"
  [[ "${rm_cluster_id}" =~ ^[A-Za-z][A-Za-z0-9._-]*$ ]] || die "rm_cluster_id must start with a letter: ${rm_cluster_id}"
  [[ "${mr_framework}" =~ ^[A-Za-z0-9._-]+$ ]] || die "mr_framework is invalid: ${mr_framework}"

  for path in "${install_dir}" "${temp_dir}" "${temp_data_dir}" "${java_path}" "${hadoop_workspace}" "${zookeeper_data_dir}"; do
    assert_abs_path "${path}"
  done
  for path in "${install_dir}" "${temp_dir}" "${temp_data_dir}"; do
    assert_deletable_path "${path}"
  done
  [[ "${install_dir}" != "${temp_dir}" && "${install_dir}" != "${temp_data_dir}" && "${temp_dir}" != "${temp_data_dir}" ]] || die "install_dir, temp_dir and temp_data_dir must be different directories"
  [[ "${hadoop_workspace}" == "${temp_data_dir}/"* ]] || die "hadoop_workspace must stay inside temp_data_dir so clean.sh can remove it"
  [[ "${zookeeper_data_dir}" == "${temp_data_dir}/"* ]] || die "zookeeper_data_dir must stay inside temp_data_dir"

  valid_port "${http_namenode_port}" || die "http_namenode_port is invalid"
  valid_port "${rpc_namenode_port}" || die "rpc_namenode_port is invalid"
  valid_port "${journal_node_port}" || die "journal_node_port is invalid"
  valid_port "${zookeeper_port}" || die "zookeeper_port is invalid"
  valid_port "${zookeeper_in_port}" || die "zookeeper_in_port is invalid"
  valid_port "${zookeeper_leader_port}" || die "zookeeper_leader_port is invalid"
  valid_port "${jobhistory_service_port}" || die "jobhistory_service_port is invalid"
  valid_port "${jobhistory_webapp_port}" || die "jobhistory_webapp_port is invalid"
  valid_port "${yarn_webapp_port}" || die "yarn_webapp_port is invalid"
  valid_port "${hbase_web_port}" || die "hbase_web_port is invalid"
  valid_port "${spark_history_ui_port}" || die "spark_history_ui_port is invalid"
  valid_port "${kafka_port}" || die "kafka_port is invalid"
  [[ "${bak_num}" =~ ^[0-9]+$ ]] || die "bak_num must be a number"
  (( bak_num >= 1 )) || die "bak_num must be at least 1"

  if is_true "${hadoop_install}"; then
    is_true "${zookeeper_install}" || die "Hadoop HA needs zookeeper_install=true"
    require_count 2 "name_node" "${name_node[@]}"
    require_count 2 "resource_manager" "${resource_manager[@]}"
    (( ${#journal_node[@]} >= 3 )) || die "journal_node needs at least 3 hosts for a quorum"
    (( ${#data_node[@]} >= 1 )) || die "data_node is empty"
    (( ${#hadoop_all_node[@]} >= 1 )) || die "hadoop_all_node is empty"
    (( bak_num <= ${#data_node[@]} )) || die "bak_num (${bak_num}) is larger than the number of data nodes (${#data_node[@]})"
    require_member "jobhistory_node" "${jobhistory_node}" "${hadoop_all_node[@]}"
    require_member "name_node" "${name_node[0]}" "${hadoop_all_node[@]}"
    require_member "name_node" "${name_node[1]}" "${hadoop_all_node[@]}"
    require_member "resource_manager" "${resource_manager[0]}" "${hadoop_all_node[@]}"
    require_member "resource_manager" "${resource_manager[1]}" "${hadoop_all_node[@]}"
    for node in "${journal_node[@]}"; do
      require_member "journal_node" "${node}" "${hadoop_all_node[@]}"
    done
    for node in "${data_node[@]}"; do
      require_member "data_node" "${node}" "${hadoop_all_node[@]}"
    done
    hosts+=("${hadoop_all_node[@]}")
  fi

  if is_true "${zookeeper_install}"; then
    (( ${#zookeeper_node[@]} >= 1 )) || die "zookeeper_node is empty"
    if (( ${#zookeeper_node[@]} % 2 == 0 )); then
      warn "ZooKeeper has an even number of nodes; use 1, 3 or 5"
    fi
    hosts+=("${zookeeper_node[@]}")
  fi

  if is_true "${spark_install}"; then
    is_true "${hadoop_install}" || die "Spark on YARN needs hadoop_install=true"
    require_member "spark_history_node" "${spark_history_node}" "${hadoop_all_node[@]}"
    [[ "${spark_history_fs_logDirectory}" == /* ]] || die "spark_history_fs_logDirectory must be an HDFS path starting with /"
    [[ "${spark_eventLog_dir}" == /* ]] || die "spark_eventLog_dir must be an HDFS path starting with /"
    [[ "${spark_yarn_archive}" == /* ]] || die "spark_yarn_archive must be an HDFS path starting with /"
  fi

  if is_true "${hbase_install}"; then
    is_true "${hadoop_install}" || die "HBase needs hadoop_install=true"
    is_true "${zookeeper_install}" || die "HBase needs zookeeper_install=true"
    (( ${#hbase_node[@]} >= 1 )) || die "hbase_node is empty"
    hosts+=("${hbase_node[@]}")
    [[ "${hbase_rootdir}" == hdfs://${cluster_name}/* ]] || die "hbase_rootdir must look like hdfs://${cluster_name}/hbase"
  fi

  if is_true "${kafka_install}"; then
    is_true "${zookeeper_install}" || die "Kafka needs zookeeper_install=true"
    (( ${#kafka_node[@]} >= 1 )) || die "kafka_node is empty"
    [[ "${kafka_logs}" == "${temp_data_dir}/"* ]] || die "kafka_logs must stay inside temp_data_dir"
    hosts+=("${kafka_node[@]}")
  fi

  if is_true "${flume_install}"; then
    (( ${#flume_node[@]} >= 1 )) || die "flume_node is empty"
    hosts+=("${flume_node[@]}")
  fi

  if is_true "${redis_install}"; then
    (( ${#redis_node[@]} >= 1 )) || die "redis_node is empty"
    (( ${#redis_ports[@]} >= 1 )) || die "redis_ports is empty"
    [[ "${redis_cluster_replicas}" =~ ^[0-9]+$ ]] || die "redis_cluster_replicas must be a number"
    [[ "${redis_cluster_conf_dir}" == "${temp_data_dir}/"* ]] || die "redis_cluster_conf_dir must stay inside temp_data_dir"
    local instances masters
    instances=$(( ${#redis_node[@]} * ${#redis_ports[@]} ))
    masters=$(( instances / (redis_cluster_replicas + 1) ))
    (( masters >= 3 )) || die "Redis cluster needs at least 3 masters; ${instances} instances with replicas=${redis_cluster_replicas} is not enough"
    (( instances % (redis_cluster_replicas + 1) == 0 )) || die "Redis instance count must divide evenly by replicas + 1"
    for port in "${redis_ports[@]}"; do
      valid_port "${port}" || die "redis port is invalid: ${port}"
      (( port + 10000 <= 65535 )) || die "redis port ${port} leaves no room for the cluster bus port"
    done
    if [[ "${redis_address}" != /* && "${redis_address}" != http://* && "${redis_address}" != https://* ]]; then
      die "redis_address must be an absolute path or an http(s) URL"
    fi
    hosts+=("${redis_node[@]}")
  fi

  hosts+=("${this_node}")
  for node in "${hosts[@]}"; do
    valid_host "${node}" || die "invalid host name: ${node}"
  done

  assert_distinct_ports
}

valid_host() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

assert_abs_path() {
  local path=$1
  [[ "${path}" == /* ]] || die "path must be absolute after the shell expands ~ : ${path}"
  if [[ "${path}" =~ [[:space:]\$\`\|\&\\\'\"] ]]; then
    die "path contains spaces or shell metacharacters: ${path}"
  fi
}

assert_deletable_path() {
  local path=$1
  local depth
  case "${path}" in
    /|/home|/root|/tmp|/opt|/usr|/var|/etc|/bin|/sbin)
      die "refusing to use a top-level directory that clean.sh would delete: ${path}"
      ;;
  esac
  depth=$(awk -F/ '{print NF-1}' <<<"${path}")
  (( depth >= 2 )) || die "path must contain at least two directories: ${path}"
}

require_count() {
  local expect=$1
  local label=$2
  shift 2
  local actual=$#
  (( actual == expect )) || die "${label} must contain exactly ${expect} hosts, found ${actual}"
}

require_member() {
  local label=$1
  local needle=$2
  shift 2
  local item
  for item in "$@"; do
    if [[ "${item}" == "${needle}" ]]; then
      return 0
    fi
  done
  die "${label} contains ${needle}, which is not in the allowed host list"
}

assert_distinct_ports() {
  local used=" "
  local entry port
  local candidates=(
    "zookeeper_port:${zookeeper_port}"
    "zookeeper_in_port:${zookeeper_in_port}"
    "zookeeper_leader_port:${zookeeper_leader_port}"
    "rpc_namenode_port:${rpc_namenode_port}"
    "http_namenode_port:${http_namenode_port}"
    "journal_node_port:${journal_node_port}"
    "jobhistory_service_port:${jobhistory_service_port}"
    "jobhistory_webapp_port:${jobhistory_webapp_port}"
    "yarn_webapp_port:${yarn_webapp_port}"
    "spark_history_ui_port:${spark_history_ui_port}"
    "kafka_port:${kafka_port}"
    "hbase_web_port:${hbase_web_port}"
  )
  for entry in "${candidates[@]}"; do
    port=${entry#*:}
    if [[ "${used}" == *" ${port} "* ]]; then
      die "port ${port} is used more than once (${entry%%:*})"
    fi
    used+="${port} "
  done
  if is_true "${redis_install}"; then
    for port in "${redis_ports[@]}"; do
      if [[ "${used}" == *" ${port} "* ]]; then
        die "redis port ${port} collides with another service"
      fi
      used+="${port} "
    done
  fi
}
