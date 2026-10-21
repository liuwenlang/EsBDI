#!/usr/bin/env bash

preflight() {
  local command_name host other home remote_home hosts=()
  local required=(bash tar ssh scp wget awk sed grep mktemp sort timeout)
  for command_name in "${required[@]}"; do
    command -v "${command_name}" >/dev/null 2>&1 || die "missing local command: ${command_name}"
  done
  if is_true "${hadoop_install}" || is_true "${zookeeper_install}" || is_true "${spark_install}" || is_true "${hbase_install}" || is_true "${kafka_install}" || is_true "${flume_install}"; then
    command -v sha512sum >/dev/null 2>&1 || die "missing local command: sha512sum"
  fi
  command -v getent >/dev/null 2>&1 || die "missing local command: getent"
  command -v ssh-keyscan >/dev/null 2>&1 || die "missing local command: ssh-keyscan"

  mapfile -t hosts < <(all_cluster_nodes)
  (( ${#hosts[@]} > 0 )) || die "no cluster nodes were configured"

  for host in "${hosts[@]}"; do
    getent hosts "${host}" >/dev/null 2>&1 || die "this machine cannot resolve ${host}. Add every node to /etc/hosts before installing."
  done

  trust_hosts "${hosts[@]}"

  for host in "${hosts[@]}"; do
    ssh_exec "${host}" "true" || die "passwordless SSH to ${linux_user_name}@${host} failed. Configure keys for every node, including this node to itself."
  done

  home=$(ssh_exec_quiet "${this_node}" 'printf %s "$HOME"')
  [[ -n "${home}" ]] || die "could not read HOME on ${this_node}"
  local same_home=false
  local path
  for path in "${install_dir}" "${temp_dir}" "${temp_data_dir}"; do
    if [[ "${path}" == "${home}" || "${path}" == "${home}/"* ]]; then
      same_home=true
    fi
  done
  for host in "${hosts[@]}"; do
    remote_home=$(ssh_exec_quiet "${host}" 'printf %s "$HOME"')
    if is_true "${same_home}" && [[ "${remote_home}" != "${home}" ]]; then
      die "${host} HOME is ${remote_home}, but ${this_node} HOME is ${home}. Use the same account and home, or move install_dir, temp_dir and temp_data_dir outside the home directory."
    fi
    ssh_exec "${host}" "test -x $(printf '%q' "${java_path}/bin/java")" || die "JDK was not found at ${java_path} on ${host}"
    ssh_exec "${host}" "command -v tar >/dev/null && command -v awk >/dev/null" || die "tar and awk are required on ${host}"
    if is_true "${hadoop_install}"; then
      ssh_exec "${host}" "command -v fuser >/dev/null" || die "fuser is not installed on ${host}. Install psmisc; Hadoop sshfence needs it."
    fi
    for other in "${hosts[@]}"; do
      ssh_exec_quiet "${host}" "getent hosts $(printf '%q' "${other}") >/dev/null" || die "${host} cannot resolve ${other}"
    done
  done

  if is_true "${hadoop_install}"; then
    if ssh_exec_quiet "${this_node}" '[[ -f "$HOME/.ssh/id_rsa" ]]'; then
      FENCING_KEY="${home}/.ssh/id_rsa"
    elif ssh_exec_quiet "${this_node}" '[[ -f "$HOME/.ssh/id_ed25519" ]]'; then
      FENCING_KEY="${home}/.ssh/id_ed25519"
    else
      die "Hadoop sshfence needs ${home}/.ssh/id_rsa or ${home}/.ssh/id_ed25519 on ${this_node}"
    fi
    for host in "${name_node[@]}"; do
      ssh_exec "${host}" "test -f $(printf '%q' "${FENCING_KEY}")" || die "Hadoop fencing key ${FENCING_KEY} is missing on ${host}"
    done
  fi

  for host in "${hosts[@]}"; do
    for other in "${hosts[@]}"; do
      ssh_exec_quiet "${host}" "ssh -o BatchMode=yes -o ConnectTimeout=15 $(printf '%q' "${linux_user_name}@${other}") true" \
        || die "${host} cannot open a passwordless SSH session to ${linux_user_name}@${other}"
    done
  done
}

trust_hosts() {
  local host scan hosts=("$@")
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
  touch "${HOME}/.ssh/known_hosts"
  chmod 600 "${HOME}/.ssh/known_hosts"
  scan=$(mktemp)
  for host in "${hosts[@]}"; do
    ssh-keyscan -T 5 -H "${host}" >> "${scan}" 2>/dev/null || die "ssh-keyscan failed for ${host}"
  done
  [[ -s "${scan}" ]] || die "ssh-keyscan returned no host keys"
  cat "${scan}" >> "${HOME}/.ssh/known_hosts"
  sort -u "${HOME}/.ssh/known_hosts" -o "${HOME}/.ssh/known_hosts"
  chmod 600 "${HOME}/.ssh/known_hosts"
  for host in "${hosts[@]}"; do
    scp "${SSH_OPTS[@]}" "${scan}" "${linux_user_name}@${host}:/tmp/esbdi-known-hosts"
    ssh_exec "${host}" "mkdir -p \"\$HOME/.ssh\" && chmod 700 \"\$HOME/.ssh\" && touch \"\$HOME/.ssh/known_hosts\" && cat /tmp/esbdi-known-hosts >> \"\$HOME/.ssh/known_hosts\" && sort -u \"\$HOME/.ssh/known_hosts\" -o \"\$HOME/.ssh/known_hosts\" && chmod 600 \"\$HOME/.ssh/known_hosts\" && rm -f /tmp/esbdi-known-hosts"
  done
  rm -f "${scan}"
}
