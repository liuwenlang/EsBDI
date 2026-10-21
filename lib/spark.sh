#!/usr/bin/env bash

prepare_spark() {
  local archive home block
  [[ -n "${hadoop_dir:-}" ]] || die "prepare Hadoop before Spark"
  archive=$(fetch_archive "${spark_address}")
  spark_dir=$(extract_staging "${archive}")
  home="${STAGING}/${spark_dir}"
  [[ -f "${home}/conf/spark-env.sh.template" ]] || die "Spark archive has no conf/spark-env.sh.template"
  [[ -f "${home}/conf/spark-defaults.conf.template" ]] || die "Spark archive has no conf/spark-defaults.conf.template"
  cp "${home}/conf/spark-env.sh.template" "${home}/conf/spark-env.sh"
  cp "${home}/conf/spark-defaults.conf.template" "${home}/conf/spark-defaults.conf"
  if [[ -f "${home}/sbin/start-all.sh" ]]; then
    mv "${home}/sbin/start-all.sh" "${home}/sbin/start-spark-all.sh"
  fi
  if [[ -f "${home}/sbin/stop-all.sh" ]]; then
    mv "${home}/sbin/stop-all.sh" "${home}/sbin/stop-spark-all.sh"
  fi
  block=$(cat <<EOF
export JAVA_HOME=${java_path}
export HADOOP_CONF_DIR=${install_dir}/${hadoop_dir}/etc/hadoop
export YARN_CONF_DIR=${install_dir}/${hadoop_dir}/etc/hadoop
EOF
)
  write_managed_block "${home}/conf/spark-env.sh" "# >>> esbdi spark-env >>>" "# <<< esbdi spark-env <<<" "${block}"
  block=$(cat <<EOF
spark.yarn.historyServer.address ${spark_history_node}:${spark_history_ui_port}
spark.history.ui.port              ${spark_history_ui_port}
spark.history.fs.logDirectory      hdfs://${cluster_name}${spark_history_fs_logDirectory}
spark.eventLog.enabled             true
spark.eventLog.dir                 hdfs://${cluster_name}${spark_eventLog_dir}
spark.eventLog.compress            true
spark.yarn.archive                 hdfs://${cluster_name}${spark_yarn_archive}/spark-jars.tar.gz
EOF
)
  write_managed_block "${home}/conf/spark-defaults.conf" "# >>> esbdi spark-defaults >>>" "# <<< esbdi spark-defaults <<<" "${block}"
  spark_archive=$(pack_tree "${spark_dir}")
}

distribute_spark() {
  distribute_archive "${spark_archive}" "${spark_dir}" "${hadoop_all_node[@]}"
}

start_spark() {
  is_true "${spark_install}" || return 0
  [[ -n "${spark_dir}" ]] || die "Spark is enabled but is not recorded in cluster state"
  local home="${install_dir}/${spark_dir}"
  local hdfs remote_tar
  hdfs="${install_dir}/${hadoop_dir}/bin/hdfs"
  remote_tar="${temp_dir}/spark-jars.tar.gz"
  log "packing Spark jars for YARN"
  ssh_exec "${name_node[0]}" "tar -C $(printf '%q' "${home}/jars") -czf $(printf '%q' "${remote_tar}") ."
  ssh_exec "${name_node[0]}" "$(printf '%q' "${hdfs}") dfs -mkdir -p $(printf '%q' "${spark_history_fs_logDirectory}") $(printf '%q' "${spark_eventLog_dir}") $(printf '%q' "${spark_yarn_archive}")"
  ssh_exec "${name_node[0]}" "$(printf '%q' "${hdfs}") dfs -chmod -R 1777 $(printf '%q' "${spark_history_fs_logDirectory}") $(printf '%q' "${spark_eventLog_dir}")"
  ssh_exec "${name_node[0]}" "$(printf '%q' "${hdfs}") dfs -put -f $(printf '%q' "${remote_tar}") $(printf '%q' "${spark_yarn_archive}/spark-jars.tar.gz")"
  if port_open "${spark_history_node}" "${spark_history_ui_port}"; then
    log "Spark history server is already listening"
    return 0
  fi
  ssh_exec "${spark_history_node}" "$(printf '%q' "${home}/sbin/start-history-server.sh")"
  wait_tcp "${spark_history_node}" "${spark_history_ui_port}" 60
}

stop_spark() {
  [[ -n "${spark_dir:-}" ]] || return 0
  local home="${install_dir}/${spark_dir}"
  ssh_exec "${spark_history_node}" "if [[ -x $(printf '%q' "${home}/sbin/stop-history-server.sh") ]]; then $(printf '%q' "${home}/sbin/stop-history-server.sh"); fi" \
    || warn "Spark history server did not stop cleanly"
}
