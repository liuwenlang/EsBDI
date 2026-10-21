#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "${ROOT}"
# shellcheck source=config.sh
source "${ROOT}/config.sh"
# shellcheck source=lib/load.sh
source "${ROOT}/lib/load.sh"

init_runtime
validate_config
clean_all
