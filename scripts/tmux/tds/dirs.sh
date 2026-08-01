#!/usr/bin/env bash
# Directory listing for tds. Sourced by tds; expects: ROOT, DEPTH, FD_CMD,
# INCLUDE_ZOXIDE and have.

emit_dirs() {
  if [[ "${INCLUDE_ZOXIDE}" == "true" ]] && have zoxide; then
    zoxide query -l 2>/dev/null || true
  fi

  if (($# > 0)); then
    "${FD_CMD}" --type d --full-path --fixed-strings --exclude .git \
      -- "$1" "${ROOT}" 2>/dev/null || true
  else
    printf '%s\n' "${ROOT}"
    "${FD_CMD}" --type d --max-depth "${DEPTH}" --exclude .git . "${ROOT}" 2>/dev/null || true
  fi
}

print_dirs() {
  local query="$*"
  local -a words=()
  local result
  local word

  if [[ -n "${query}" ]]; then
    read -r -a words <<< "${query}"
  fi

  if ((${#words[@]} > 0)); then
    result="$(emit_dirs "${words[0]}")"
    for word in "${words[@]}"; do
      result="$(grep -F -- "${word}" <<< "${result}" || true)"
    done
  else
    result="$(emit_dirs)"
  fi

  printf '%s\n' "${result}" | sed 's:/\+$::' | awk 'NF && !seen[$0]++'
}
