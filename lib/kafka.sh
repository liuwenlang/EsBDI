#!/usr/bin/env bash

prepare_kafka() {
  local archive home block rf isr
  archive=$(fetch_archive "${kafka_address}")
  kafka_dir=$(extract_staging "${archive}")
  home="${STAGING}/${kafka_dir}"
  [[ -f "${home}/config/server.properties" ]] || die "Kafka archive has no config/server.properties"
  rf=${#kafka_node[@]}
  if (( rf > 3 )); then
    rf=3
  fi
  if (( rf > 1 )); then
    isr=$((rf - 1))
  else
    isr=1
  fi
  block=$(cat <<EOF
log.dirs=${kafka_logs}
zookeeper.connect=$(join_host_port "${zookeeper_port}" "," "${zookeeper_node[@]}")
listeners=PLAINTEXT://:${kafka_port}
num.partitions=${rf}
default.replication.factor=${rf}
offsets.topic.replication.factor=${rf}
transaction.state.log.replication.factor=${rf}
transaction.state.log.min.isr=${isr}
EOF
)
  write_managed_block "${home}/config/server.properties" "# >>> esbdi kafka >>>" "# <<< esbdi kafka <<<" "${block}"
  kafka_archive=$(pack_tree "${kafka_dir}")
}

distribute_kafka() {
  distribute_archive "${kafka_archive}" "${kafka_dir}" "${kafka_node[@]}"
  local index=0 host home block
  home="${install_dir}/${kafka_dir}"
  for host in "${kafka_node[@]}"; do
    block=$(cat <<EOF
broker.id=${index}
advertised.listeners=PLAINTEXT://${host}:${kafka_port}
EOF
)
    ssh_exec "${host}" "mkdir -p $(printf '%q' "${kafka_logs}")
$(declare -f write_managed_block)
write_managed_block $(printf '%q' "${home}/config/server.properties") '# >>> esbdi kafka broker >>>' '# <<< esbdi kafka broker <<<' $(printf '%q' "${block}")"
    index=$((index + 1))
  done
}

start_kafka() {
  is_true "${kafka_install}" || return 0
  [[ -n "${kafka_dir}" ]] || die "Kafka is enabled but is not recorded in cluster state"
  local host home="${install_dir}/${kafka_dir}"
  for host in "${kafka_node[@]}"; do
    if port_open "${host}" "${kafka_port}"; then
      log "Kafka is already listening on ${host}:${kafka_port}"
      continue
    fi
    ssh_exec "${host}" "$(printf '%q' "${home}/bin/kafka-server-start.sh") -daemon $(printf '%q' "${home}/config/server.properties")"
    wait_tcp "${host}" "${kafka_port}" 60
  done
}

stop_kafka() {
  [[ -n "${kafka_dir:-}" ]] || return 0
  local host home="${install_dir}/${kafka_dir}"
  for host in "${kafka_node[@]}"; do
    ssh_exec "${host}" "if [[ -x $(printf '%q' "${home}/bin/kafka-server-stop.sh") ]]; then $(printf '%q' "${home}/bin/kafka-server-stop.sh"); fi" \
      || warn "Kafka did not stop cleanly on ${host}"
  done
}
