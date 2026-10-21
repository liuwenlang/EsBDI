#!/usr/bin/env bash

detect_redis_bins() {
  local root=$1
  if [[ -x "${root}/src/redis-server" && -x "${root}/src/redis-cli" ]]; then
    redis_server_rel="src/redis-server"
    redis_cli_rel="src/redis-cli"
  elif [[ -x "${root}/bin/redis-server" && -x "${root}/bin/redis-cli" ]]; then
    redis_server_rel="bin/redis-server"
    redis_cli_rel="bin/redis-cli"
  elif [[ -x "${root}/redis-server" && -x "${root}/redis-cli" ]]; then
    redis_server_rel="redis-server"
    redis_cli_rel="redis-cli"
  else
    die "redis-server and redis-cli were not found. redis_address must be a compiled tarball with one top-level directory."
  fi
}

redis_announce_ip() {
  local host=$1
  local ip
  ip=$(getent ahostsv4 "${host}" | awk 'NR==1 { print $1 }')
  [[ -n "${ip}" ]] || die "cannot resolve ${host} to an IPv4 address for Redis"
  printf '%s\n' "${ip}"
}

write_redis_conf() {
  local dest=$1
  local port=$2
  local dir=$3
  local ip=$4
  local bus=$((port + 10000))
  mkdir -p "$(dirname "${dest}")"
  cat > "${dest}" <<EOF
bind 0.0.0.0
protected-mode no
port ${port}
tcp-keepalive 300
daemonize yes
supervised no
pidfile ${dir}/redis.pid
logfile ${dir}/redis.log
dir ${dir}
dbfilename dump.rdb
appendonly no
cluster-enabled yes
cluster-config-file ${dir}/nodes.conf
cluster-node-timeout 15000
cluster-announce-ip ${ip}
cluster-announce-port ${port}
cluster-announce-bus-port ${bus}
EOF
}

prepare_redis() {
  local archive
  archive=$(fetch_archive "${redis_address}")
  redis_dir=$(extract_staging "${archive}")
  detect_redis_bins "${STAGING}/${redis_dir}"
  redis_archive=$(pack_tree "${redis_dir}")
}

distribute_redis() {
  distribute_archive "${redis_archive}" "${redis_dir}" "${redis_node[@]}"
  local host port ip dir conf
  for host in "${redis_node[@]}"; do
    ip=$(redis_announce_ip "${host}")
    ssh_exec "${host}" "mkdir -p $(printf '%q' "${redis_cluster_conf_dir}")"
    for port in "${redis_ports[@]}"; do
      dir="${redis_cluster_conf_dir}/${port}"
      conf="${DIST}/redis-${host}-${port}.conf"
      write_redis_conf "${conf}" "${port}" "${dir}" "${ip}"
      ssh_exec "${host}" "mkdir -p $(printf '%q' "${dir}")"
      scp "${SSH_OPTS[@]}" "${conf}" "${linux_user_name}@${host}:${dir}/redis.conf"
    done
  done
}

start_redis() {
  is_true "${redis_install}" || return 0
  [[ -n "${redis_dir}" && -n "${redis_server_rel}" ]] || die "Redis is enabled but is not recorded in cluster state"
  local host port home server cli
  home="${install_dir}/${redis_dir}"
  server="${home}/${redis_server_rel}"
  cli="${home}/${redis_cli_rel}"
  for host in "${redis_node[@]}"; do
    for port in "${redis_ports[@]}"; do
      if port_open "${host}" "${port}"; then
        log "Redis is already listening on ${host}:${port}"
        continue
      fi
      ssh_exec "${host}" "$(printf '%q' "${server}") $(printf '%q' "${redis_cluster_conf_dir}/${port}/redis.conf")"
      wait_tcp "${host}" "${port}" 30
    done
  done
  if [[ -n "${redis_create_command}" ]]; then
    log "running custom Redis cluster command"
    ssh_exec "${redis_node[0]}" "${redis_create_command}"
    return 0
  fi
  local first_ip first_port info endpoints=()
  first_ip=$(redis_announce_ip "${redis_node[0]}")
  first_port=${redis_ports[0]}
  info=$(ssh_exec_quiet "${redis_node[0]}" "$(printf '%q' "${cli}") -h $(printf '%q' "${first_ip}") -p ${first_port} cluster info" || true)
  if [[ "${info}" == *"cluster_state:ok"* ]]; then
    log "Redis cluster is already initialized"
    return 0
  fi
  for host in "${redis_node[@]}"; do
    local ip
    ip=$(redis_announce_ip "${host}")
    for port in "${redis_ports[@]}"; do
      endpoints+=("${ip}:${port}")
    done
  done
  log "creating Redis cluster"
  ssh_exec "${redis_node[0]}" "printf 'yes\n' | $(printf '%q' "${cli}") --cluster create ${endpoints[*]} --cluster-replicas ${redis_cluster_replicas}"
}

stop_redis() {
  [[ -n "${redis_dir:-}" && -n "${redis_cli_rel:-}" ]] || return 0
  local host port cli="${install_dir}/${redis_dir}/${redis_cli_rel}"
  for host in "${redis_node[@]}"; do
    for port in "${redis_ports[@]}"; do
      ssh_exec "${host}" "if [[ -x $(printf '%q' "${cli}") ]]; then $(printf '%q' "${cli}") -p ${port} shutdown nosave || true; fi" \
        || warn "Redis did not stop cleanly on ${host}:${port}"
    done
  done
}
