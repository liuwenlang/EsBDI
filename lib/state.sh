#!/usr/bin/env bash

write_state() {
  mkdir -p "$(dirname "${STATE_FILE}")"
  cat > "${STATE_FILE}" <<EOF
hadoop_dir=$(printf '%q' "${hadoop_dir:-}")
zookeeper_dir=$(printf '%q' "${zookeeper_dir:-}")
spark_dir=$(printf '%q' "${spark_dir:-}")
hbase_dir=$(printf '%q' "${hbase_dir:-}")
kafka_dir=$(printf '%q' "${kafka_dir:-}")
flume_dir=$(printf '%q' "${flume_dir:-}")
redis_dir=$(printf '%q' "${redis_dir:-}")
redis_server_rel=$(printf '%q' "${redis_server_rel:-}")
redis_cli_rel=$(printf '%q' "${redis_cli_rel:-}")
EOF
}

publish_state() {
  local host content
  content=$(<"${STATE_FILE}")
  for host in "$@"; do
    ssh_exec "${host}" "mkdir -p $(printf '%q' "${install_dir}") && cat > $(printf '%q' "${install_dir}/esbdi-state.sh") <<'ESBDI_EOF'
${content}
ESBDI_EOF"
  done
}

load_state() {
  if [[ -f "${STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${STATE_FILE}"
    return 0
  fi
  if [[ -f "${install_dir}/esbdi-state.sh" ]]; then
    # shellcheck disable=SC1090
    source "${install_dir}/esbdi-state.sh"
    return 0
  fi
  return 1
}

require_state() {
  load_state || die "cluster state was not found. Run install.sh on this machine first."
}

assign_glob() {
  local var_name=$1
  shift
  if [[ -n "${!var_name:-}" ]]; then
    return 0
  fi
  local pattern item matches=()
  for pattern in "$@"; do
    for item in "${install_dir}"/${pattern}; do
      if [[ -d "${item}" ]]; then
        matches+=("$(basename "${item}")")
      fi
    done
  done
  if (( ${#matches[@]} == 1 )); then
    printf -v "${var_name}" '%s' "${matches[0]}"
  elif (( ${#matches[@]} > 1 )); then
    warn "found more than one ${var_name} directory in ${install_dir}: ${matches[*]}"
  fi
}

detect_installed_dirs() {
  local previous
  previous=$(shopt -p nullglob || true)
  shopt -s nullglob
  assign_glob hadoop_dir 'hadoop-*'
  assign_glob zookeeper_dir 'zookeeper-*'
  assign_glob spark_dir 'spark-*'
  assign_glob hbase_dir 'hbase-*'
  assign_glob kafka_dir 'kafka_*' 'kafka-*'
  assign_glob flume_dir 'apache-flume-*'
  assign_glob redis_dir 'redis' 'redis-*'
  if [[ -n "${redis_dir:-}" && -z "${redis_server_rel:-}" ]]; then
    if [[ -x "${install_dir}/${redis_dir}/src/redis-server" ]]; then
      redis_server_rel="src/redis-server"
      redis_cli_rel="src/redis-cli"
    elif [[ -x "${install_dir}/${redis_dir}/bin/redis-server" ]]; then
      redis_server_rel="bin/redis-server"
      redis_cli_rel="bin/redis-cli"
    elif [[ -x "${install_dir}/${redis_dir}/redis-server" ]]; then
      redis_server_rel="redis-server"
      redis_cli_rel="redis-cli"
    fi
  fi
  eval "${previous}"
}
