#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ONN_SCRIPT="${SCRIPTS_DIR}/onn"

if [[ ! -f "${ONN_SCRIPT}" ]]; then
  echo "Missing: ${ONN_SCRIPT}" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

export HOME="${TMPDIR}/home"
mkdir -p "${HOME}"

VAULT="${TMPDIR}/vault"
export ONN_VAULT="${VAULT}"
export ONN_NOTE_DIR="${VAULT}/0 Inbox"
export ONN_DAILY_DIR="${VAULT}/Daily"
export ONN_TEMPLATE_DIR="${VAULT}/3 Resources/templates"

mkdir -p "${ONN_NOTE_DIR}" "${ONN_DAILY_DIR}" "${ONN_TEMPLATE_DIR}"

export ONN_MEETING_DIR="${VAULT}/Meetings"
mkdir -p "${ONN_MEETING_DIR}"

cat > "${ONN_TEMPLATE_DIR}/meeting.md" <<EOF
---
template: meeting
title: {{title}}
date: {{date}}
created: {{created}}
---

TEMPLATE:meeting
EOF

cat > "${ONN_TEMPLATE_DIR}/person.md" <<EOF
---
template: person
title: {{title}}
date: {{date}}
created: {{created}}
---

TEMPLATE:person
EOF

cat > "${ONN_TEMPLATE_DIR}/_Project.md" <<EOF
---
template: project
title: {{title}}
date: {{date}}
created: {{created}}
---

TEMPLATE:project
EOF

cat > "${ONN_TEMPLATE_DIR}/incident.md" <<EOF
---
template: incident
title: {{title}}
date: {{date}}
created: {{created}}
---

TEMPLATE:incident
EOF

cat > "${ONN_TEMPLATE_DIR}/improvement.md" <<EOF
---
template: improvement
title: {{title}}
date: {{date}}
created: {{created}}
---

TEMPLATE:improvement
EOF

cat > "${ONN_TEMPLATE_DIR}/decision.md" <<EOF
---
template: decision
title: {{title}}
date: {{date}}
created: {{created}}
---

TEMPLATE:decision
EOF

cat > "${ONN_TEMPLATE_DIR}/enablement.md" <<EOF
---
template: enablement
title: {{title}}
date: {{date}}
created: {{created}}
---

TEMPLATE:enablement
EOF

cat > "${ONN_TEMPLATE_DIR}/operational.md" <<EOF
---
template: operational
title: {{title}}
date: {{date}}
created: {{created}}
---

TEMPLATE:operational
EOF

cat > "${ONN_TEMPLATE_DIR}/commitment.md" <<EOF
---
template: commitment
title: {{title}}
date: {{date}}
created: {{created}}
---

TEMPLATE:commitment
EOF

MOCK_BIN="${TMPDIR}/bin"
mkdir -p "${MOCK_BIN}"

cat > "${MOCK_BIN}/mockeditor" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
f=""
for arg in "$@"; do
  if [[ -f "${arg}" ]]; then
    f="${arg}"
  fi
done
if [[ -n "${f}" ]]; then
  printf "\nedited\n" >> "${f}"
fi
exit 0
EOF
chmod +x "${MOCK_BIN}/mockeditor"

export PATH="${MOCK_BIN}:${PATH}"
export EDITOR="mockeditor"

assert_file_exists() {
  local f="$1"
  if [[ ! -f "${f}" ]]; then
    echo "Expected file to exist: ${f}" >&2
    exit 1
  fi
}

assert_file_contains() {
  local f="$1"
  local needle="$2"
  if ! grep -q "${needle}" "${f}"; then
    echo "Expected file to contain: ${needle}" >&2
    echo "File: ${f}" >&2
    exit 1
  fi
}

run_and_check() {
  local flag="$1"
  local title="$2"
  local expected_marker="$3"
  local expected_slug="$4"
  local expected_dir="${5:-$ONN_NOTE_DIR}"

  bash "${ONN_SCRIPT}" "${flag}" "${title}" >/dev/null

  local out_file="${expected_dir}/${expected_slug}.md"
  assert_file_exists "${out_file}"
  assert_file_contains "${out_file}" "${expected_marker}"
  assert_file_contains "${out_file}" "title: ${title}"
}

run_and_check "--meeting" "Weekly Sync" "TEMPLATE:meeting" "weekly-sync" "${ONN_MEETING_DIR}"
run_and_check "--person" "Ada Lovelace" "TEMPLATE:person" "ada-lovelace" "${VAULT}/3 Resources/people"
run_and_check "--project" "My Project" "TEMPLATE:project" "my-project" "${VAULT}/4 Companies/Invexsa/Projects"
run_and_check "--incident" "DB Outage" "TEMPLATE:incident" "db-outage" "${VAULT}/4 Companies/Invexsa/Incidents"
run_and_check "--improvement" "Make Deploy Safer" "TEMPLATE:improvement" "make-deploy-safer" "${VAULT}/4 Companies/Invexsa/Improvements"
run_and_check "--decision" "Use Postgres" "TEMPLATE:decision" "use-postgres" "${VAULT}/4 Companies/Invexsa/Decisions"
run_and_check "--enablement" "Improve Onboarding" "TEMPLATE:enablement" "improve-onboarding" "${VAULT}/4 Companies/Invexsa/Enablement"
run_and_check "--operational" "Rotate Secrets" "TEMPLATE:operational" "rotate-secrets" "${VAULT}/4 Companies/Invexsa/Operations"
run_and_check "--commitment" "Write Weekly Update" "TEMPLATE:commitment" "write-weekly-update" "${VAULT}/4 Companies/Invexsa/Commitments"

CUSTOM_TEMPLATE="${TMPDIR}/custom.md"
cat > "${CUSTOM_TEMPLATE}" <<EOF
---
template: custom
title: {{title}}
---

TEMPLATE:custom
EOF

bash "${ONN_SCRIPT}" --template "${CUSTOM_TEMPLATE}" "Custom Note" >/dev/null
assert_file_exists "${ONN_NOTE_DIR}/custom-note.md"
assert_file_contains "${ONN_NOTE_DIR}/custom-note.md" "TEMPLATE:custom"

bash "${ONN_SCRIPT}" --meeting --template "${CUSTOM_TEMPLATE}" "Override Template" >/dev/null
assert_file_exists "${ONN_NOTE_DIR}/override-template.md"
assert_file_contains "${ONN_NOTE_DIR}/override-template.md" "TEMPLATE:custom"

echo "OK"
