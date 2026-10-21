#!/usr/bin/env bash

write_hbase_host_files() {
  local dest=$1
  shift
  mkdir -p "${dest}"
  if (( $# == 0 )); then
    : > "${dest}/regionservers"
    : > "${dest}/backup-masters"
    return 0
  fi
  printf '%s\n' "$@" > "${dest}/regionservers"
  if (( $# > 1 )); then
    shift
    printf '%s\n' "$@" > "${dest}/backup-masters"
  else
    : > "${dest}/backup-masters"
  fi
}

prepare_hbase() {
  local archive home block hosts quorum
  [[ -n "${hadoop_dir:-}" ]] || die "prepare Hadoop before HBase"
  archive=$(fetch_archive "${hbase_address}")
  hbase_dir=$(extract_staging "${archive}")
  home="${STAGING}/${hbase_dir}"
  [[ -f "${home}/conf/hbase-env.sh" ]] || die "HBase archive has no conf/hbase-env.sh"
  [[ -f "${home}/conf/hbase-site.xml" ]] || die "HBase archive has no conf/hbase-site.xml"
  hosts=$(join_by "," "${hbase_node[@]}")
  quorum=$(join_by "," "${zookeeper_node[@]}")
  render_template "${ROOT}/resource/hbase/hbase-site.xml" "${home}/conf/hbase-site.xml" \
    "HBASE_ROOTDIR=${hbase_rootdir}" \
    "ZK_HOSTS=${quorum}" \
    "ZK_PORT=${zookeeper_port}"
  write_hbase_host_files "${home}/conf" "${hbase_node[@]}"
  block=$(cat <<EOF
export JAVA_HOME=${java_path}
export HBASE_MANAGES_ZK=false
EOF
)
  write_managed_block "${home}/conf/hbase-env.sh" "# >>> esbdi hbase-env >>>" "# <<< esbdi hbase-env <<<" "${block}"
  cp "${STAGING}/${hadoop_dir}/etc/hadoop/core-site.xml" "${home}/conf/core-site.xml"
  cp "${STAGING}/${hadoop_dir}/etc/hadoop/hdfs-site.xml" "${home}/conf/hdfs-site.xml"
  hbase_archive=$(pack_tree "${hbase_dir}")
  # hosts is used to keep the joined list available for logs without a shellcheck warning.
  log "HBase regionservers: ${hosts}"
}

distribute_hbase() {
  distribute_archive "${hbase_archive}" "${hbase_dir}" "${hbase_node[@]}"
}

start_hbase() {
  is_true "${hbase_install}" || return 0
  [[ -n "${hbase_dir}" ]] || die "HBase is enabled but is not recorded in cluster state"
  local home="${install_dir}/${hbase_dir}"
  local hdfs="${install_dir}/${hadoop_dir}/bin/hdfs"
  ssh_exec "${name_node[0]}" "$(printf '%q' "${hdfs}") dfs -mkdir -p /hbase"
  if port_open "${hbase_node[0]}" "${hbase_web_port}"; then
    log "HBase master is already listening"
    return 0
  fi
  ssh_exec "${hbase_node[0]}" "$(printf '%q' "${home}/bin/start-hbase.sh")"
  wait_tcp "${hbase_node[0]}" "${hbase_web_port}" 90
}

stop_hbase() {
  [[ -n "${hbase_dir:-}" ]] || return 0
  local home="${install_dir}/${hbase_dir}"
  ssh_exec "${hbase_node[0]}" "if [[ -x $(printf '%q' "${home}/bin/stop-hbase.sh") ]]; then $(printf '%q' "${home}/bin/stop-hbase.sh"); fi" \
    || warn "HBase did not stop cleanly"
}
