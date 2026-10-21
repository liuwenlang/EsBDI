#!/usr/bin/env bash

install_all() {
  reset_component_dirs
  mkdir -p "${STAGING}" "${DIST}"
  if is_true "${zookeeper_install}"; then
    log "preparing ZooKeeper"
    prepare_zookeeper
  fi
  if is_true "${hadoop_install}"; then
    log "preparing Hadoop"
    prepare_hadoop
  fi
  if is_true "${spark_install}"; then
    log "preparing Spark"
    prepare_spark
  fi
  if is_true "${hbase_install}"; then
    log "preparing HBase"
    prepare_hbase
  fi
  if is_true "${kafka_install}"; then
    log "preparing Kafka"
    prepare_kafka
  fi
  if is_true "${flume_install}"; then
    log "preparing Flume"
    prepare_flume
  fi
  if is_true "${redis_install}"; then
    log "preparing Redis"
    prepare_redis
  fi

  if is_true "${zookeeper_install}"; then
    distribute_zookeeper
  fi
  if is_true "${hadoop_install}"; then
    distribute_hadoop
  fi
  if is_true "${spark_install}"; then
    distribute_spark
  fi
  if is_true "${hbase_install}"; then
    distribute_hbase
  fi
  if is_true "${kafka_install}"; then
    distribute_kafka
  fi
  if is_true "${flume_install}"; then
    distribute_flume
  fi
  if is_true "${redis_install}"; then
    distribute_redis
  fi

  write_state
  local hosts=()
  mapfile -t hosts < <(all_cluster_nodes)
  publish_state "${hosts[@]}"
  publish_cluster_env "${hosts[@]}"

  if is_true "${start_services}"; then
    start_all
  else
    log "start_services is false. Run bash start-all.sh when you want the daemons."
  fi
  print_endpoints
}

start_all() {
  require_state
  start_zookeeper
  start_hadoop
  start_spark
  start_hbase
  start_kafka
  start_redis
  start_flume
}

stop_all() {
  if ! load_state; then
    detect_installed_dirs || true
  fi
  stop_redis || true
  stop_flume || true
  stop_kafka || true
  stop_hbase || true
  stop_spark || true
  stop_hadoop || true
  stop_zookeeper || true
}

clean_all() {
  log "stopping services before deleting directories"
  stop_all || true
  local hosts=() host
  mapfile -t hosts < <(all_cluster_nodes)
  for host in "${hosts[@]}"; do
    log "cleaning ${host}"
    ssh_exec "${host}" "rm -rf $(printf '%q' "${install_dir}") $(printf '%q' "${temp_data_dir}") $(printf '%q' "${temp_dir}") && rm -f \"\$HOME/zookeeper.out\"" \
      || warn "could not delete data directories on ${host}"
    strip_remote_bashrc "${host}" || true
  done
  rm -f "${STATE_FILE:?}"
  rm -rf "${ROOT:?}/var"
  log "clean finished"
}

status_all() {
  if ! load_state; then
    detect_installed_dirs || true
  fi
  local hosts=() host
  mapfile -t hosts < <(all_cluster_nodes)
  for host in "${hosts[@]}"; do
    printf '\n== %s ==\n' "${host}"
    ssh_exec "${host}" "$(printf '%q' "${java_path}/bin/jps") -l" || warn "jps failed on ${host}"
  done
  print_endpoints
}

print_endpoints() {
  printf '\nCluster endpoints\n'
  if is_true "${hadoop_install}"; then
    printf 'HDFS NameNode:  http://%s:%s  http://%s:%s\n' \
      "${name_node[0]}" "${http_namenode_port}" "${name_node[1]}" "${http_namenode_port}"
    printf 'YARN:           http://%s:%s  http://%s:%s\n' \
      "${resource_manager[0]}" "${yarn_webapp_port}" "${resource_manager[1]}" "${yarn_webapp_port}"
    printf 'JobHistory:     http://%s:%s\n' "${jobhistory_node}" "${jobhistory_webapp_port}"
  fi
  if is_true "${spark_install}"; then
    printf 'Spark history:  http://%s:%s\n' "${spark_history_node}" "${spark_history_ui_port}"
  fi
  if is_true "${hbase_install}"; then
    printf 'HBase master:   http://%s:%s\n' "${hbase_node[0]}" "${hbase_web_port}"
  fi
  if is_true "${zookeeper_install}"; then
    printf 'ZooKeeper:      %s\n' "$(join_host_port "${zookeeper_port}" "," "${zookeeper_node[@]}")"
  fi
  if is_true "${kafka_install}"; then
    printf 'Kafka:          %s\n' "$(join_host_port "${kafka_port}" "," "${kafka_node[@]}")"
  fi
  if is_true "${redis_install}"; then
    local host port
    printf 'Redis:'
    for host in "${redis_node[@]}"; do
      for port in "${redis_ports[@]}"; do
        printf ' %s:%s' "${host}" "${port}"
      done
    done
    printf '\n'
    printf 'Redis has no password and listens on every interface. Keep it on a lab network.\n'
  fi
}
