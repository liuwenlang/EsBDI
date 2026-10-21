#!/usr/bin/env bash
# Unit checks for the installer. They do not touch a cluster.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../lib/load.sh
source "${ROOT}/lib/load.sh"

failures=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

assert_eq() {
  local actual=$1
  local expected=$2
  local label=$3
  if [[ "${actual}" != "${expected}" ]]; then
    fail "${label}: expected [${expected}] got [${actual}]"
  fi
}

test_join_and_unique() {
  assert_eq "$(join_by "," a b c)" "a,b,c" "join comma"
  assert_eq "$(join_host_port 2181 ";" bd01 bd02)" "bd01:2181;bd02:2181" "journal quorum"
  assert_eq "$(unique_nodes bd01 bd02 bd01 bd03)" $'bd01\nbd02\nbd03' "unique nodes"
}

test_templates_are_xml() {
  local out zk
  out=$(mktemp)
  zk=$(join_host_port 2181 "," bd01 bd02 bd03)
  render_template "${ROOT}/resource/hadoop/core-site.xml" "${out}" \
    "CLUSTER_NAME=mycluster" \
    "HADOOP_TMP=/data/hadoop" \
    "ZK_QUORUM=${zk}"
  xmllint --noout "${out}" || fail "core-site xml"
  grep -q '<value>hdfs://mycluster</value>' "${out}" || fail "default fs"
  grep -q '<value>bd01:2181,bd02:2181,bd03:2181</value>' "${out}" || fail "zk quorum"

  render_template "${ROOT}/resource/hadoop/hdfs-site.xml" "${out}" \
    "CLUSTER_NAME=mycluster" \
    "NN1_RPC=bd01:8020" \
    "NN2_RPC=bd02:8020" \
    "NN1_HTTP=bd01:50070" \
    "NN2_HTTP=bd02:50070" \
    "REPLICATION=2" \
    "JOURNAL_QUORUM=$(join_host_port 8485 ";" bd01 bd02 bd03)" \
    "JOURNAL_DIR=/data/hadoop/journal" \
    "NAME_DIR=/data/hadoop/namenode" \
    "DATA_DIR=/data/hadoop/datanode" \
    "FENCING_KEY=/home/hadoop/.ssh/id_rsa"
  xmllint --noout "${out}" || fail "hdfs-site xml"
  grep -q 'dfs.journalnode.edits.dir' "${out}" || fail "journal dir property"
  grep -q 'sshfence' "${out}" || fail "sshfence"
  if grep -q 'shell(/bin/true)' "${out}" || grep -q 'exampleuser' "${out}"; then
    fail "unsafe fencing snippet still present"
  fi

  render_template "${ROOT}/resource/hadoop/yarn-site.xml" "${out}" \
    "RM_CLUSTER_ID=yrc" "RM1=bd01" "RM2=bd02" "YARN_WEBAPP_PORT=8088" "ZK_QUORUM=${zk}"
  xmllint --noout "${out}" || fail "yarn-site xml"
  render_template "${ROOT}/resource/hadoop/mapred-site.xml" "${out}" \
    "MR_FRAMEWORK=yarn" \
    "JOBHISTORY_ADDRESS=bd01:10020" \
    "JOBHISTORY_WEBAPP=bd01:19888"
  xmllint --noout "${out}" || fail "mapred-site xml"
  grep -q 'bd01:19888' "${out}" || fail "jobhistory web port"

  render_template "${ROOT}/resource/hbase/hbase-site.xml" "${out}" \
    "HBASE_ROOTDIR=hdfs://mycluster/hbase" \
    "ZK_HOSTS=bd01,bd02,bd03" \
    "ZK_PORT=2181"
  xmllint --noout "${out}" || fail "hbase-site xml"
  grep -q '<value>bd01,bd02,bd03</value>' "${out}" || fail "hbase quorum must be hostnames"
  if grep -q 'bd01:2181' "${out}"; then
    fail "hbase quorum must not embed the client port"
  fi
  rm -f "${out}"
}

test_hbase_host_files() {
  local dir
  dir=$(mktemp -d)
  write_hbase_host_files "${dir}" bd01 bd02 bd03
  assert_eq "$(cat "${dir}/regionservers")" $'bd01\nbd02\nbd03' "regionservers"
  assert_eq "$(cat "${dir}/backup-masters")" $'bd02\nbd03' "backup masters"
  if grep -q '^bd01$' "${dir}/backup-masters"; then
    fail "active master was also written as its own backup"
  fi
  write_hbase_host_files "${dir}" bd01
  assert_eq "$(cat "${dir}/regionservers")" "bd01" "single regionserver"
  [[ ! -s "${dir}/backup-masters" ]] || fail "single node should not have a backup master"
  rm -rf "${dir}"
}

test_managed_block_is_idempotent() {
  local file
  file=$(mktemp)
  printf 'keep\n' > "${file}"
  write_managed_block "${file}" "# begin" "# end" $'one\ntwo'
  write_managed_block "${file}" "# begin" "# end" $'one\ntwo'
  assert_eq "$(cat "${file}")" $'keep\n# begin\none\ntwo\n# end' "managed block"
  rm -f "${file}"
}

test_ssh_script_keeps_remote_dollars() {
  local script body
  java_path=/opt/jdk
  install_dir=/home/hadoop/apps
  body=$(declare -f write_managed_block)
  script=$(build_ssh_script "${body}"$'\n'"echo \$HOME")
  [[ "${script}" == *'local file=$1'* ]] || fail "function arguments were expanded locally"
  [[ "${script}" == *'echo $HOME'* ]] || fail "remote dollar was expanded locally"
  [[ "${script}" == *'export JAVA_HOME=/opt/jdk'* ]] || fail "JAVA_HOME was not pinned"
}

test_cluster_env_path() {
  local env
  java_path=/opt/jdk
  install_dir=/opt/apps
  hadoop_dir=hadoop-2.7.7
  zookeeper_dir=""
  spark_dir=""
  hbase_dir=""
  kafka_dir=""
  flume_dir=""
  redis_dir=""
  env=$(build_cluster_env)
  [[ "${env}" == *'export JAVA_HOME=/opt/jdk'* ]] || fail "cluster env java"
  [[ "${env}" == *'export HADOOP_HOME=/opt/apps/hadoop-2.7.7'* ]] || fail "cluster env hadoop"
  [[ "${env}" == *'export PATH="$JAVA_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH"'* ]] || fail "cluster env path: ${env}"
}

test_state_roundtrip_and_detect() {
  local work
  work=$(mktemp -d)
  STATE_FILE="${work}/cluster-state.sh"
  install_dir="${work}/apps"
  hadoop_dir="hadoop-2.7.7"
  zookeeper_dir=""
  spark_dir=""
  hbase_dir=""
  kafka_dir=""
  flume_dir=""
  redis_dir="redis"
  redis_server_rel="src/redis-server"
  redis_cli_rel="src/redis-cli"
  write_state
  hadoop_dir=""
  redis_dir=""
  redis_server_rel=""
  redis_cli_rel=""
  load_state || fail "load_state"
  assert_eq "${hadoop_dir}" "hadoop-2.7.7" "state hadoop dir"
  assert_eq "${redis_server_rel}" "src/redis-server" "state redis bin"

  mkdir -p "${install_dir}/zookeeper-3.4.14/bin" "${install_dir}/redis/src"
  touch "${install_dir}/redis/src/redis-server" "${install_dir}/redis/src/redis-cli"
  chmod +x "${install_dir}/redis/src/redis-server" "${install_dir}/redis/src/redis-cli"
  rm -f "${STATE_FILE}"
  hadoop_dir=""
  zookeeper_dir=""
  redis_dir=""
  redis_server_rel=""
  redis_cli_rel=""
  detect_installed_dirs
  assert_eq "${zookeeper_dir}" "zookeeper-3.4.14" "detected zookeeper"
  assert_eq "${redis_dir}" "redis" "detected redis"
  assert_eq "${redis_server_rel}" "src/redis-server" "detected redis server"
  rm -rf "${work}"
}

test_archive_topdir() {
  local work archive top
  work=$(mktemp -d)
  mkdir -p "${work}/demo-component/conf"
  printf 'x\n' > "${work}/demo-component/conf/a.txt"
  archive="${work}/demo.tar.gz"
  tar -C "${work}" -czf "${archive}" demo-component
  top=$(archive_topdir "${archive}")
  assert_eq "${top}" "demo-component" "archive top directory"
  rm -rf "${work}"
}

test_checksums() {
  local name sum
  for name in hadoop-2.7.7.tar.gz zookeeper-3.4.14.tar.gz spark-2.4.7-bin-hadoop2.7.tgz hbase-2.2.4-bin.tar.gz kafka_2.11-2.4.1.tgz apache-flume-1.9.0-bin.tar.gz; do
    sum=$(expected_sha512 "https://example.invalid/${name}") || fail "missing checksum ${name}"
    [[ "${#sum}" -eq 128 ]] || fail "checksum length ${name}"
    [[ "${sum}" =~ ^[0-9a-f]+$ ]] || fail "checksum charset ${name}"
  done
  if expected_sha512 "https://example.invalid/custom.tar.gz"; then
    fail "custom archive should not have a pinned checksum"
  fi
}

test_redis_conf() {
  local file ip
  file=$(mktemp)
  write_redis_conf "${file}" 6380 /data/redis/6380 192.168.0.11
  grep -q '^port 6380$' "${file}" || fail "redis port"
  grep -q '^pidfile /data/redis/6380/redis.pid$' "${file}" || fail "redis pidfile"
  grep -q '^cluster-config-file /data/redis/6380/nodes.conf$' "${file}" || fail "redis nodes conf"
  grep -q '^cluster-announce-port 6380$' "${file}" || fail "redis announce port"
  grep -q '^cluster-announce-bus-port 16380$' "${file}" || fail "redis bus port"
  rm -f "${file}"
  ip=$(redis_announce_ip localhost)
  [[ -n "${ip}" ]] || fail "localhost did not resolve"
}

test_shipped_config_is_valid() {
  (
    # shellcheck source=../config.sh
    source "${ROOT}/config.sh"
    validate_config
    [[ "${jobhistory_node}" == "bd01" ]]
    [[ "${spark_history_node}" == "bd01" ]]
  ) || fail "shipped config.sh failed validation"
}

expect_invalid() {
  local label=$1
  shift
  if "$@"; then
    fail "${label} was accepted"
  fi
}

test_config_rejections() {
  expect_invalid "hadoop without zookeeper" bash -c "
    set -euo pipefail
    ROOT='${ROOT}'
    source \"\$ROOT/config.sh\"
    source \"\$ROOT/lib/load.sh\"
    zookeeper_install=false
    validate_config
  "
  expect_invalid "single namenode" bash -c "
    set -euo pipefail
    ROOT='${ROOT}'
    source \"\$ROOT/config.sh\"
    source \"\$ROOT/lib/load.sh\"
    name_node=(bd01)
    validate_config
  "
  expect_invalid "broad temp dir" bash -c "
    set -euo pipefail
    ROOT='${ROOT}'
    source \"\$ROOT/config.sh\"
    source \"\$ROOT/lib/load.sh\"
    temp_dir=/tmp
    validate_config
  "
  expect_invalid "path with a space" bash -c "
    set -euo pipefail
    ROOT='${ROOT}'
    source \"\$ROOT/config.sh\"
    source \"\$ROOT/lib/load.sh\"
    install_dir='/home/hadoop/my apps'
    validate_config
  "
  expect_invalid "too few redis nodes" bash -c "
    set -euo pipefail
    ROOT='${ROOT}'
    source \"\$ROOT/config.sh\"
    source \"\$ROOT/lib/load.sh\"
    redis_install=true
    redis_node=(bd01)
    redis_address=/tmp/redis.tar.gz
    validate_config
  "
}

test_static_regressions() {
  local hits
  hits=$(grep -R -n -E 'exampleuser|shell\(/bin/true\)|if \[ i == 0 \]|node_manager|192\.168\.0\.202' \
    "${ROOT}/lib" "${ROOT}/resource" "${ROOT}/config.sh" "${ROOT}"/*.sh || true)
  if [[ -n "${hits}" ]]; then
    fail "old snippets are still present:${hits}"
  fi
}

test_bash_syntax() {
  local file
  while IFS= read -r file; do
    bash -n "${file}" || fail "bash -n ${file}"
  done < <(find "${ROOT}" -name '*.sh' -type f | sort)
}

test_join_and_unique
test_templates_are_xml
test_hbase_host_files
test_managed_block_is_idempotent
test_ssh_script_keeps_remote_dollars
test_cluster_env_path
test_state_roundtrip_and_detect
test_archive_topdir
test_checksums
test_redis_conf
test_shipped_config_is_valid
test_config_rejections
test_static_regressions
test_bash_syntax

if (( failures > 0 )); then
  printf '%s test failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'ok\n'
