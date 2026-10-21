#!/usr/bin/env bash
# 日志、SSH 和文件块。被 source，不要直接执行。

log() {
  local line
  line="[$(date '+%F %T')] $*"
  printf '%s\n' "$line" >&2
  if [[ -n "${LOG_FILE:-}" ]]; then
    printf '%s\n' "$line" >> "${LOG_FILE}" || true
  fi
}

die() {
  log "ERROR: $*"
  exit 1
}

warn() {
  log "WARN: $*"
}

is_true() {
  [[ "${1:-}" == "true" ]]
}

init_ssh_opts() {
  SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15)
  if ssh -G -o StrictHostKeyChecking=accept-new localhost >/dev/null 2>&1; then
    SSH_OPTS+=(-o StrictHostKeyChecking=accept-new)
  fi
}

init_runtime() {
  mkdir -p "${temp_dir}/logs" "${temp_dir}/dist" "${temp_dir}/staging" "${ROOT}/var"
  LOG_FILE="${temp_dir}/logs/esbdi.log"
  STATE_FILE="${ROOT}/var/cluster-state.sh"
  STAGING="${temp_dir}/staging"
  DIST="${temp_dir}/dist"
  init_ssh_opts
}

build_ssh_script() {
  local script=$1
  cat <<EOF
set -euo pipefail
export JAVA_HOME=$(printf '%q' "${java_path}")
export PATH="\$JAVA_HOME/bin:\$PATH"
if [[ -f $(printf '%q' "${install_dir}/cluster-env.sh") ]]; then
  # shellcheck disable=SC1091
  source $(printf '%q' "${install_dir}/cluster-env.sh")
fi
${script}
EOF
}

ssh_exec() {
  local host=$1
  local script=$2
  local quiet=${3:-false}
  local remote
  if ! is_true "$quiet"; then
    log "ssh ${linux_user_name}@${host}"
  fi
  remote=$(build_ssh_script "$script")
  ssh "${SSH_OPTS[@]}" "${linux_user_name}@${host}" "bash -s" <<<"${remote}"
}

ssh_exec_quiet() {
  ssh_exec "$1" "$2" true
}

port_open() {
  ssh_exec_quiet "$1" "bash -c 'echo >/dev/tcp/127.0.0.1/${2}'" >/dev/null 2>&1
}

wait_tcp() {
  local host=$1
  local port=$2
  local seconds=${3:-60}
  local elapsed=0
  log "waiting for ${host}:${port}"
  while (( elapsed < seconds )); do
    if ssh_exec_quiet "${host}" "bash -c 'echo >/dev/tcp/127.0.0.1/${port}'" >/dev/null 2>&1; then
      log "${host}:${port} is up"
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  die "timed out after ${seconds}s waiting for ${host}:${port}"
}

write_managed_block() {
  local file=$1
  local begin=$2
  local end=$3
  local content=$4
  local tmp
  mkdir -p "$(dirname "${file}")"
  touch "${file}"
  tmp=$(mktemp)
  awk -v b="${begin}" -v e="${end}" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    skip != 1 { print }
  ' "${file}" > "${tmp}"
  {
    cat "${tmp}"
    printf '%s\n' "${begin}"
    printf '%s\n' "${content}"
    printf '%s\n' "${end}"
  } > "${file}"
  rm -f "${tmp}"
}

strip_managed_block() {
  local file=$1
  local begin=$2
  local end=$3
  local tmp
  [[ -f "${file}" ]] || return 0
  tmp=$(mktemp)
  awk -v b="${begin}" -v e="${end}" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    skip != 1 { print }
  ' "${file}" > "${tmp}"
  mv "${tmp}" "${file}"
}

reset_component_dirs() {
  hadoop_dir=""
  zookeeper_dir=""
  spark_dir=""
  hbase_dir=""
  kafka_dir=""
  flume_dir=""
  redis_dir=""
  redis_server_rel=""
  redis_cli_rel=""
}
