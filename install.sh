#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "${ROOT}"
# shellcheck source=config.sh
source "${ROOT}/config.sh"
# shellcheck source=lib/load.sh
source "${ROOT}/lib/load.sh"

case "${1:-}" in
  "") ;;
  --no-start) start_services=false ;;
  -h|--help)
    cat <<EOF
Usage: bash install.sh [--no-start]

Reads config.sh, installs the selected components and starts them.
--no-start leaves the daemons stopped so you can run bash start-all.sh later.
EOF
    exit 0
    ;;
  *)
    die "unknown argument: $1"
    ;;
esac

init_runtime
validate_config
preflight
install_all
