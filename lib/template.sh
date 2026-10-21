#!/usr/bin/env bash
# 把 @NAME@ 替换成参数里的值。参数形式是 NAME=value。

xml_escape() {
  local value=$1
  value=${value//&/&amp;}
  value=${value//</&lt;}
  value=${value//>/&gt;}
  value=${value//\"/&quot;}
  printf '%s\n' "${value}"
}

render_template() {
  local src=$1
  local dest=$2
  shift 2
  local text pair key value leftover
  text=$(<"${src}")
  for pair in "$@"; do
    key=${pair%%=*}
    value=${pair#*=}
    text=${text//"@${key}@"/${value}}
  done
  leftover=$(printf '%s\n' "${text}" | grep -oE '@[A-Z0-9_]+@' || true)
  if [[ -n "${leftover}" ]]; then
    die "unreplaced placeholders in ${dest}: ${leftover}"
  fi
  mkdir -p "$(dirname "${dest}")"
  printf '%s\n' "${text}" > "${dest}"
}
