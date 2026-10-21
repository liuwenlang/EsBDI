#!/usr/bin/env bash

prepare_flume() {
  local archive home block
  archive=$(fetch_archive "${flume_address}")
  flume_dir=$(extract_staging "${archive}")
  home="${STAGING}/${flume_dir}"
  [[ -f "${home}/conf/flume-env.sh.template" ]] || die "Flume archive has no conf/flume-env.sh.template"
  cp "${home}/conf/flume-env.sh.template" "${home}/conf/flume-env.sh"
  block=$(cat <<EOF
export JAVA_HOME=${java_path}
EOF
)
  write_managed_block "${home}/conf/flume-env.sh" "# >>> esbdi flume-env >>>" "# <<< esbdi flume-env <<<" "${block}"
  cp "${ROOT}/resource/flume/esbdi-example.conf" "${home}/conf/esbdi-example.conf"
  flume_archive=$(pack_tree "${flume_dir}")
}

distribute_flume() {
  distribute_archive "${flume_archive}" "${flume_dir}" "${flume_node[@]}"
}

start_flume() {
  is_true "${flume_install}" || return 0
  [[ -n "${flume_dir}" ]] || die "Flume is enabled but is not recorded in cluster state"
  log "Flume is installed but not started. Example agent: ${install_dir}/${flume_dir}/conf/esbdi-example.conf"
}

stop_flume() {
  [[ -n "${flume_dir:-}" ]] || return 0
  local host home="${install_dir}/${flume_dir}"
  for host in "${flume_node[@]}"; do
    ssh_exec "${host}" "pids=\$(pgrep -f $(printf '%q' "${home}") || true); for pid in \$pids; do if [[ \"\$pid\" -ne \$\$ && \"\$pid\" -ne \$PPID ]]; then kill -TERM \"\$pid\" || true; fi; done" \
      || warn "Flume did not stop cleanly on ${host}"
  done
}
