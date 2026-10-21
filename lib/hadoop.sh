#!/usr/bin/env bash

prepare_hadoop() {
  local archive home conf block quorum journal
  [[ -n "${FENCING_KEY:-}" ]] || die "FENCING_KEY is empty. Run preflight before preparing Hadoop."
  archive=$(fetch_archive "${hadoop_address}")
  hadoop_dir=$(extract_staging "${archive}")
  home="${STAGING}/${hadoop_dir}"
  conf="${home}/etc/hadoop"
  [[ -d "${conf}" ]] || die "Hadoop archive has no etc/hadoop directory"
  if [[ -f "${conf}/workers" && ! -f "${conf}/slaves" ]]; then
    die "this installer targets Hadoop 2.7. The archive looks like Hadoop 3 because it has workers and no slaves file."
  fi
  [[ -f "${conf}/slaves" ]] || die "Hadoop archive has no etc/hadoop/slaves file"

  quorum=$(join_host_port "${zookeeper_port}" "," "${zookeeper_node[@]}")
  journal=$(join_host_port "${journal_node_port}" ";" "${journal_node[@]}")
  render_template "${ROOT}/resource/hadoop/core-site.xml" "${conf}/core-site.xml" \
    "CLUSTER_NAME=${cluster_name}" \
    "HADOOP_TMP=$(xml_escape "${hadoop_workspace}")" \
    "ZK_QUORUM=${quorum}"
  render_template "${ROOT}/resource/hadoop/hdfs-site.xml" "${conf}/hdfs-site.xml" \
    "CLUSTER_NAME=${cluster_name}" \
    "NN1_RPC=${name_node[0]}:${rpc_namenode_port}" \
    "NN2_RPC=${name_node[1]}:${rpc_namenode_port}" \
    "NN1_HTTP=${name_node[0]}:${http_namenode_port}" \
    "NN2_HTTP=${name_node[1]}:${http_namenode_port}" \
    "REPLICATION=${bak_num}" \
    "JOURNAL_QUORUM=${journal}" \
    "JOURNAL_DIR=$(xml_escape "${hadoop_workspace}/journal")" \
    "NAME_DIR=$(xml_escape "${hadoop_workspace}/namenode")" \
    "DATA_DIR=$(xml_escape "${hadoop_workspace}/datanode")" \
    "FENCING_KEY=$(xml_escape "${FENCING_KEY}")"
  render_template "${ROOT}/resource/hadoop/yarn-site.xml" "${conf}/yarn-site.xml" \
    "RM_CLUSTER_ID=${rm_cluster_id}" \
    "RM1=${resource_manager[0]}" \
    "RM2=${resource_manager[1]}" \
    "YARN_WEBAPP_PORT=${yarn_webapp_port}" \
    "ZK_QUORUM=${quorum}"
  render_template "${ROOT}/resource/hadoop/mapred-site.xml" "${conf}/mapred-site.xml" \
    "MR_FRAMEWORK=${mr_framework}" \
    "JOBHISTORY_ADDRESS=${jobhistory_node}:${jobhistory_service_port}" \
    "JOBHISTORY_WEBAPP=${jobhistory_node}:${jobhistory_webapp_port}"
  printf '%s\n' "${data_node[@]}" > "${conf}/slaves"

  block=$(cat <<EOF
export JAVA_HOME=${java_path}
export HADOOP_HOME=${install_dir}/${hadoop_dir}
export HADOOP_SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=15"
EOF
)
  write_managed_block "${conf}/hadoop-env.sh" "# >>> esbdi hadoop-env >>>" "# <<< esbdi hadoop-env <<<" "${block}"
  hadoop_archive=$(pack_tree "${hadoop_dir}")
}

distribute_hadoop() {
  distribute_archive "${hadoop_archive}" "${hadoop_dir}" "${hadoop_all_node[@]}"
}

hadoop_bin() {
  printf '%s/%s/bin/hdfs\n' "${install_dir}" "${hadoop_dir}"
}

hadoop_sbin() {
  printf '%s/%s/sbin\n' "${install_dir}" "${hadoop_dir}"
}

start_hadoop() {
  is_true "${hadoop_install}" || return 0
  [[ -n "${hadoop_dir}" ]] || die "Hadoop is enabled but is not recorded in cluster state"
  local host sbin bin name_dir marker
  sbin=$(hadoop_sbin)
  bin=$(hadoop_bin)
  name_dir="${hadoop_workspace}/namenode"
  for host in "${hadoop_all_node[@]}"; do
    ssh_exec "${host}" "mkdir -p $(printf '%q' "${hadoop_workspace}/namenode") $(printf '%q' "${hadoop_workspace}/datanode") $(printf '%q' "${hadoop_workspace}/journal")"
  done

  marker=$(ssh_exec_quiet "${name_node[0]}" "if [[ -f $(printf '%q' "${name_dir}/current/VERSION") ]]; then echo yes; else echo no; fi") || die "could not check NameNode metadata on ${name_node[0]}"
  [[ "${marker}" == "yes" || "${marker}" == "no" ]] || die "unexpected NameNode metadata check result: ${marker}"
  if [[ "${marker}" == "yes" ]]; then
    log "NameNode metadata already exists, format will be skipped"
  else

    for host in "${journal_node[@]}"; do
      ssh_exec "${host}" "$(printf '%q' "${sbin}/hadoop-daemon.sh") start journalnode"
    done
    for host in "${journal_node[@]}"; do
      wait_tcp "${host}" "${journal_node_port}" 90
    done
    ssh_exec "${name_node[0]}" "$(printf '%q' "${bin}") namenode -format -force -nonInteractive"
    ssh_exec "${name_node[0]}" "$(printf '%q' "${sbin}/hadoop-daemon.sh") start namenode"
    wait_tcp "${name_node[0]}" "${rpc_namenode_port}" 120
    ssh_exec "${name_node[1]}" "$(printf '%q' "${bin}") namenode -bootstrapStandby -force -nonInteractive"
    ssh_exec "${name_node[0]}" "$(printf '%q' "${bin}") zkfc -formatZK -force -nonInteractive"
  fi

  ssh_exec "${name_node[0]}" "$(printf '%q' "${sbin}/start-dfs.sh")"
  log "waiting for HDFS to leave safemode"
  ssh_exec "${name_node[0]}" "timeout 180 $(printf '%q' "${bin}") dfsadmin -safemode wait"
  ssh_exec "${resource_manager[0]}" "$(printf '%q' "${sbin}/start-yarn.sh")"
  if [[ "${resource_manager[1]}" != "${resource_manager[0]}" ]]; then
    ssh_exec "${resource_manager[1]}" "$(printf '%q' "${sbin}/yarn-daemon.sh") start resourcemanager"
  fi
  ssh_exec "${jobhistory_node}" "$(printf '%q' "${sbin}/mr-jobhistory-daemon.sh") start historyserver"
}

stop_hadoop() {
  [[ -n "${hadoop_dir:-}" ]] || return 0
  local sbin
  sbin=$(hadoop_sbin)
  ssh_exec "${jobhistory_node}" "if [[ -x $(printf '%q' "${sbin}/mr-jobhistory-daemon.sh") ]]; then $(printf '%q' "${sbin}/mr-jobhistory-daemon.sh") stop historyserver; fi" \
    || warn "JobHistory did not stop cleanly"
  ssh_exec "${resource_manager[0]}" "if [[ -x $(printf '%q' "${sbin}/stop-yarn.sh") ]]; then $(printf '%q' "${sbin}/stop-yarn.sh"); fi" \
    || warn "YARN did not stop cleanly on ${resource_manager[0]}"
  if [[ "${resource_manager[1]}" != "${resource_manager[0]}" ]]; then
    ssh_exec "${resource_manager[1]}" "if [[ -x $(printf '%q' "${sbin}/yarn-daemon.sh") ]]; then $(printf '%q' "${sbin}/yarn-daemon.sh") stop resourcemanager; fi" \
      || warn "ResourceManager did not stop cleanly on ${resource_manager[1]}"
  fi
  ssh_exec "${name_node[0]}" "if [[ -x $(printf '%q' "${sbin}/stop-dfs.sh") ]]; then $(printf '%q' "${sbin}/stop-dfs.sh"); fi" \
    || warn "HDFS did not stop cleanly"
}
