#!/usr/bin/env bash

build_cluster_env() {
  local path_front="\$JAVA_HOME/bin"
  cat <<EOF
export JAVA_HOME=$(printf '%q' "${java_path}")
EOF
  if [[ -n "${hadoop_dir:-}" ]]; then
    cat <<EOF
export HADOOP_HOME=$(printf '%q' "${install_dir}/${hadoop_dir}")
export HADOOP_CONF_DIR="\$HADOOP_HOME/etc/hadoop"
export YARN_CONF_DIR="\$HADOOP_HOME/etc/hadoop"
EOF
    path_front+=":\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin"
  fi
  if [[ -n "${zookeeper_dir:-}" ]]; then
    cat <<EOF
export ZOOKEEPER_HOME=$(printf '%q' "${install_dir}/${zookeeper_dir}")
EOF
    path_front+=":\$ZOOKEEPER_HOME/bin"
  fi
  if [[ -n "${spark_dir:-}" ]]; then
    cat <<EOF
export SPARK_HOME=$(printf '%q' "${install_dir}/${spark_dir}")
EOF
    path_front+=":\$SPARK_HOME/bin:\$SPARK_HOME/sbin"
  fi
  if [[ -n "${hbase_dir:-}" ]]; then
    cat <<EOF
export HBASE_HOME=$(printf '%q' "${install_dir}/${hbase_dir}")
EOF
    path_front+=":\$HBASE_HOME/bin"
  fi
  if [[ -n "${kafka_dir:-}" ]]; then
    cat <<EOF
export KAFKA_HOME=$(printf '%q' "${install_dir}/${kafka_dir}")
EOF
    path_front+=":\$KAFKA_HOME/bin"
  fi
  if [[ -n "${flume_dir:-}" ]]; then
    cat <<EOF
export FLUME_HOME=$(printf '%q' "${install_dir}/${flume_dir}")
EOF
    path_front+=":\$FLUME_HOME/bin"
  fi
  if [[ -n "${redis_dir:-}" ]]; then
    cat <<EOF
export REDIS_HOME=$(printf '%q' "${install_dir}/${redis_dir}")
export REDIS_SERVER="\$REDIS_HOME/${redis_server_rel}"
export REDIS_CLI="\$REDIS_HOME/${redis_cli_rel}"
EOF
  fi
  printf 'export PATH="%s:$PATH"\n' "${path_front}"
}

publish_cluster_env() {
  local host content
  content=$(build_cluster_env)
  for host in "$@"; do
    ssh_exec "${host}" "cat > $(printf '%q' "${install_dir}/cluster-env.sh") <<'ESBDI_EOF'
${content}
ESBDI_EOF
chmod 644 $(printf '%q' "${install_dir}/cluster-env.sh")"
    ssh_exec "${host}" "$(declare -f write_managed_block)
write_managed_block \"\$HOME/.bashrc\" '# >>> esbdi >>>' '# <<< esbdi <<<' $(printf '%q' "if [[ -f '${install_dir}/cluster-env.sh' ]]; then
  # shellcheck disable=SC1091
  source '${install_dir}/cluster-env.sh'
fi")"
  done
}

strip_remote_bashrc() {
  local host=$1
  ssh_exec "${host}" "$(declare -f strip_managed_block)
strip_managed_block \"\$HOME/.bashrc\" '# >>> esbdi >>>' '# <<< esbdi <<<'" || warn "could not update bashrc on ${host}"
}
