#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMMAND_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
BUDA_SEND="${COMMAND_DIR}/buda-send"

TMPDIR="$(mktemp -d)"
trap 'rm -rf -- "$TMPDIR"' EXIT

MOCK_BIN="${TMPDIR}/bin"
CONTENT_ROOT="${TMPDIR}/content"
mkdir -p -- "$MOCK_BIN" "$CONTENT_ROOT"

cat > "${MOCK_BIN}/scp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-}" == -- ]] && shift
source_file="$1"
remote_file="${2#*:}"
cp -- "$source_file" "$remote_file"
EOF

cat > "${MOCK_BIN}/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

shift
bash -c "$1"
EOF

chmod +x "${MOCK_BIN}/scp" "${MOCK_BIN}/ssh"
export PATH="${MOCK_BIN}:${PATH}"
export BUDA_SERVER="test-server"
export BUDA_CONTENT_ROOT="$CONTENT_ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1" expected="$2"
  grep -Fq -- "$expected" "$file" || fail "$file no contiene: $expected"
}

ESSAY="${TMPDIR}/essay.md"
cat > "$ESSAY" <<'EOF'
+++
publication_type = "essay"
slug = "primer-ensayo"
draft = true
+++

Contenido.
draft = "no modificar el cuerpo"
EOF

bash "$BUDA_SEND" "$ESSAY" >/dev/null
ESSAY_TARGET="${CONTENT_ROOT}/essays/primer-ensayo.md"
[[ -f "$ESSAY_TARGET" ]] || fail "no se creo el ensayo"
assert_contains "$ESSAY_TARGET" 'draft = false'
assert_contains "$ESSAY_TARGET" 'draft = "no modificar el cuerpo"'

NOTE="${TMPDIR}/note.md"
cat > "$NOTE" <<'EOF'
+++
publication_type = 'note'
slug = 'primera-nota'
draft = false
+++

Contenido.
EOF

bash "$BUDA_SEND" --draft "$NOTE" >/dev/null
NOTE_TARGET="${CONTENT_ROOT}/notes/primera-nota.md"
[[ -f "$NOTE_TARGET" ]] || fail "no se creo la nota"
assert_contains "$NOTE_TARGET" 'draft = true'

if bash "$BUDA_SEND" "$ESSAY" >/dev/null 2>&1; then
  fail "se sobrescribio una publicacion existente"
fi

INVALID="${TMPDIR}/invalid.md"
cat > "$INVALID" <<'EOF'
+++
publication_type = "page"
slug = "pagina"
draft = false
+++
EOF

if bash "$BUDA_SEND" "$INVALID" >/dev/null 2>&1; then
  fail "se acepto un publication_type invalido"
fi

BODY_ONLY="${TMPDIR}/body-only.md"
cat > "$BODY_ONLY" <<'EOF'
+++
title = "Sin campos requeridos"
+++

publication_type = "essay"
slug = "campos-en-el-cuerpo"
draft = false
EOF

if bash "$BUDA_SEND" "$BODY_ONLY" >/dev/null 2>&1; then
  fail "se aceptaron campos fuera del frontmatter"
fi

CONCURRENT="${TMPDIR}/concurrent.md"
cat > "$CONCURRENT" <<'EOF'
+++
publication_type = "note"
slug = "envio-simultaneo"
draft = false
+++
EOF

bash "$BUDA_SEND" "$CONCURRENT" >/dev/null 2>&1 &
pid_one=$!
bash "$BUDA_SEND" "$CONCURRENT" >/dev/null 2>&1 &
pid_two=$!

status_one=0
status_two=0
wait "$pid_one" || status_one=$?
wait "$pid_two" || status_two=$?

if [[ $status_one -eq 0 && $status_two -eq 0 ]] ||
  [[ $status_one -ne 0 && $status_two -ne 0 ]]; then
  fail "los envios simultaneos no produjeron exactamente un ganador"
fi

if bash "$BUDA_SEND" "${TMPDIR}/missing.md" >/dev/null 2>&1; then
  fail "se acepto un archivo inexistente"
fi

echo "OK"
