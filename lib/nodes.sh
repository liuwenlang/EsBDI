#!/usr/bin/env bash

join_by() {
  local separator=$1
  shift
  local item output=""
  for item in "$@"; do
    if [[ -z "${output}" ]]; then
      output=${item}
    else
      output+="${separator}${item}"
    fi
  done
  printf '%s\n' "${output}"
}

join_host_port() {
  local port=$1
  local separator=$2
  shift 2
  local host items=()
  for host in "$@"; do
    items+=("${host}:${port}")
  done
  if (( ${#items[@]} == 0 )); then
    printf '\n'
    return 0
  fi
  join_by "${separator}" "${items[@]}"
}

unique_nodes() {
  local node seen=" " output=()
  for node in "$@"; do
    if [[ "${seen}" != *" ${node} "* ]]; then
      seen+="${node} "
      output+=("${node}")
    fi
  done
  if (( ${#output[@]} > 0 )); then
    printf '%s\n' "${output[@]}"
  fi
}

all_cluster_nodes() {
  local nodes=("${this_node}")
  if is_true "${hadoop_install}"; then
    nodes+=("${hadoop_all_node[@]}" "${journal_node[@]}" "${name_node[@]}" "${resource_manager[@]}" "${data_node[@]}")
    if [[ -n "${jobhistory_node}" ]]; then
      nodes+=("${jobhistory_node}")
    fi
  fi
  if is_true "${zookeeper_install}"; then
    nodes+=("${zookeeper_node[@]}")
  fi
  if is_true "${spark_install}" && [[ -n "${spark_history_node}" ]]; then
    nodes+=("${spark_history_node}")
  fi
  if is_true "${hbase_install}"; then
    nodes+=("${hbase_node[@]}")
  fi
  if is_true "${kafka_install}"; then
    nodes+=("${kafka_node[@]}")
  fi
  if is_true "${flume_install}"; then
    nodes+=("${flume_node[@]}")
  fi
  if is_true "${redis_install}"; then
    nodes+=("${redis_node[@]}")
  fi
  unique_nodes "${nodes[@]}"
}
