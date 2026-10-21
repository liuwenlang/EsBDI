#!/usr/bin/env bash

fetch_archive() {
  local url=$1
  local dest partial
  dest="${DIST}/$(basename "${url%%\?*}")"
  mkdir -p "${DIST}"
  if [[ "${url}" == /* ]]; then
    [[ -f "${url}" ]] || die "local archive not found: ${url}"
    cp -f "${url}" "${dest}"
  elif [[ "${url}" == http://* || "${url}" == https://* ]]; then
    log "downloading ${url}"
    partial="${dest}.partial"
    wget --tries=3 --timeout=30 -O "${partial}" "${url}" || die "download failed: ${url}"
    mv -f "${partial}" "${dest}"
  else
    die "archive location must be an absolute path or an http(s) URL: ${url}"
  fi
  verify_sha512 "${url}" "${dest}"
  printf '%s\n' "${dest}"
}

verify_sha512() {
  local url=$1
  local file=$2
  local expect actual
  if ! expect=$(expected_sha512 "${url}"); then
    log "no pinned checksum for $(basename "${file}"), skipped"
    return 0
  fi
  command -v sha512sum >/dev/null 2>&1 || die "sha512sum is required to verify $(basename "${file}")"
  actual=$(sha512sum "${file}" | awk '{print $1}')
  actual=${actual,,}
  expect=${expect,,}
  [[ "${actual}" == "${expect}" ]] || die "checksum mismatch for ${file}"
  log "checksum ok $(basename "${file}")"
}

archive_topdir() {
  local archive=$1
  local list first
  list=$(mktemp)
  tar -tzf "${archive}" > "${list}"
  first=$(head -n 1 "${list}" || true)
  rm -f "${list}"
  first=${first%%/*}
  [[ -n "${first}" && "${first}" != "." ]] || die "archive has no single top-level directory: ${archive}"
  printf '%s\n' "${first}"
}

extract_staging() {
  local archive=$1
  local top
  top=$(archive_topdir "${archive}")
  mkdir -p "${STAGING}"
  rm -rf "${STAGING:?}/${top}"
  tar -xzf "${archive}" -C "${STAGING}"
  [[ -d "${STAGING}/${top}" ]] || die "archive did not extract to ${top}: ${archive}"
  printf '%s\n' "${top}"
}

pack_tree() {
  local top=$1
  local archive="${DIST}/${top}.tar.gz"
  tar -C "${STAGING}" -czf "${archive}" "${top}"
  printf '%s\n' "${archive}"
}

distribute_archive() {
  local archive=$1
  local top=$2
  shift 2
  local host base
  base=$(basename "${archive}")
  for host in "$@"; do
    log "distribute ${base} -> ${host}"
    ssh_exec "${host}" "mkdir -p $(printf '%q' "${install_dir}") $(printf '%q' "${temp_dir}") $(printf '%q' "${temp_data_dir}")"
    scp "${SSH_OPTS[@]}" "${archive}" "${linux_user_name}@${host}:${temp_dir}/${base}"
    ssh_exec "${host}" "rm -rf $(printf '%q' "${install_dir}/${top}") && tar -xzf $(printf '%q' "${temp_dir}/${base}") -C $(printf '%q' "${install_dir}")"
  done
}
