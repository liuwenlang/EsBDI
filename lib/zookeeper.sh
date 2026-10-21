#!/usr/bin/env bash

prepare_zookeeper() {
  local archive home index host servers
  archive=$(fetch_archive "${zookeeper_address}")
  zookeeper_dir=$(extract_staging "${archive}")
  home="${STAGING}/${zookeeper_dir}"
  [[ -f "${home}/conf/zoo_sample.cfg" ]] || die "ZooKeeper archive has no conf/zoo_sample.cfg"
  cp "${home}/conf/zoo_sample.cfg" "${home}/conf/zoo.cfg"
  sed -i "s|^dataDir=.*|dataDir=${zookeeper_data_dir}|" "${home}/conf/zoo.cfg"
  sed -i "s|^clientPort=.*|clientPort=${zookeeper_port}|" "${home}/conf/zoo.cfg"
  servers=""
  index=1
  for host in "${zookeeper_node[@]}"; do
    servers+="server.${index}=${host}:${zookeeper_in_port}:${zookeeper_leader_port}"$'\n'
    index=$((index + 1))
  done
  write_managed_block "${home}/conf/zoo.cfg" "# >>> esbdi zookeeper >>>" "# <<< esbdi zookeeper <<<" "${servers%$'\n'}"
  zookeeper_archive=$(pack_tree "${zookeeper_dir}")
}

distribute_zookeeper() {
  distribute_archive "${zookeeper_archive}" "${zookeeper_dir}" "${zookeeper_node[@]}"
  local index=1 host
  for host in "${zookeeper_node[@]}"; do
    ssh_exec "${host}" "mkdir -p $(printf '%q' "${zookeeper_data_dir}") && printf '%s\n' '${index}' > $(printf '%q' "${zookeeper_data_dir}/myid")"
    index=$((index + 1))
  done
}

start_zookeeper() {
  is_true "${zookeeper_install}" || return 0
  [[ -n "${zookeeper_dir}" ]] || die "ZooKeeper is enabled but is not recorded in cluster state"
  local host home="${install_dir}/${zookeeper_dir}"
  for host in "${zookeeper_node[@]}"; do
    if port_open "${host}" "${zookeeper_port}"; then
      log "ZooKeeper is already listening on ${host}:${zookeeper_port}"
      continue
    fi
    ssh_exec "${host}" "$(printf '%q' "${home}/bin/zkServer.sh") start"
  done
  for host in "${zookeeper_node[@]}"; do
    wait_tcp "${host}" "${zookeeper_port}" 60
  done
}

stop_zookeeper() {
  [[ -n "${zookeeper_dir:-}" ]] || return 0
  local host home="${install_dir}/${zookeeper_dir}"
  for host in "${zookeeper_node[@]}"; do
    ssh_exec "${host}" "if [[ -x $(printf '%q' "${home}/bin/zkServer.sh") ]]; then $(printf '%q' "${home}/bin/zkServer.sh") stop; fi; rm -f \"\$HOME/zookeeper.out\"" \
      || warn "ZooKeeper did not stop cleanly on ${host}"
  done
}
