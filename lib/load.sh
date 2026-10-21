#!/usr/bin/env bash
# 按依赖顺序加载函数。调用方需要先设置 ROOT。

if [[ -z "${ROOT:-}" ]]; then
  echo "ROOT is not set" >&2
  exit 1
fi

# shellcheck source=common.sh
source "${ROOT}/lib/common.sh"
# shellcheck source=template.sh
source "${ROOT}/lib/template.sh"
# shellcheck source=nodes.sh
source "${ROOT}/lib/nodes.sh"
# shellcheck source=checksums.sh
source "${ROOT}/lib/checksums.sh"
# shellcheck source=download.sh
source "${ROOT}/lib/download.sh"
# shellcheck source=state.sh
source "${ROOT}/lib/state.sh"
# shellcheck source=env.sh
source "${ROOT}/lib/env.sh"
# shellcheck source=validate.sh
source "${ROOT}/lib/validate.sh"
# shellcheck source=preflight.sh
source "${ROOT}/lib/preflight.sh"
# shellcheck source=zookeeper.sh
source "${ROOT}/lib/zookeeper.sh"
# shellcheck source=hadoop.sh
source "${ROOT}/lib/hadoop.sh"
# shellcheck source=spark.sh
source "${ROOT}/lib/spark.sh"
# shellcheck source=hbase.sh
source "${ROOT}/lib/hbase.sh"
# shellcheck source=kafka.sh
source "${ROOT}/lib/kafka.sh"
# shellcheck source=flume.sh
source "${ROOT}/lib/flume.sh"
# shellcheck source=redis.sh
source "${ROOT}/lib/redis.sh"
# shellcheck source=lifecycle.sh
source "${ROOT}/lib/lifecycle.sh"
