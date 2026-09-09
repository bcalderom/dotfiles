#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly config_root="$(dirname -- "$script_dir")"
readonly repo_root="$(git -C "$config_root" rev-parse --show-toplevel)"
readonly relative_root="${config_root#"$repo_root"/}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

readonly -a required_agents=(
  architect engineer explore advisor document review version
)
readonly -a removed_agents=(docs-writer evidence-checker)

python3 - "$config_root" "${required_agents[@]}" "${removed_agents[@]}" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
required = set(sys.argv[2:9])
removed = set(sys.argv[9:11])

base = json.loads((root / "config.json").read_text(encoding="utf-8"))

assert base["share"] == "disabled"
assert base["autoupdate"] == "notify"
assert base["small_model"] == "openai/gpt-5.5"
assert base["subagent_depth"] == 1
assert len(base["mcp"]) == 16
assert {
    name for name, mcp in base["mcp"].items() if mcp.get("enabled", True)
} == {"context7", "jcodemunch"}

# explore is defined as a file agent, not in config.json.
assert "explore" not in base.get("agent", {}), (
    "explore must be defined in agent/explore.md only"
)

# general (native subagent) must not launch pipeline specialists.
# NOTE: the task deny must live under permission.task; a top-level "task" key
# is routed to options and silently ignored (verified against opencode 1.18.29).
general = base.get("agent", {}).get("general", {})
assert general.get("permission", {}).get("task") == "deny", (
    "native general agent must deny task under permission.task in config.json"
)

agents_dir = root / "agent"
present = {p.stem for p in agents_dir.glob("*.md")}
assert required <= present, f"missing agents: {sorted(required - present)}"
assert not (present & removed), f"agents must be removed: {sorted(present & removed)}"

# Agent frontmatter expectations.
frontmatter = {}
for name in required:
    text = (agents_dir / f"{name}.md").read_text(encoding="utf-8")
    meta = {}
    inside = False
    for line in text.splitlines():
        if line.strip() == "---":
            inside = not inside
            continue
        if inside:
            key, _, value = line.partition(":")
            meta[key.strip()] = value.strip()
    frontmatter[name] = meta

expectations = {
    "architect": {"mode": "primary", "model": "openai/gpt-5.6-sol", "variant": "medium"},
    "engineer": {"mode": "primary", "model": "opencode/glm-5.3-flash"},
    "explore": {"mode": "subagent", "hidden": "true", "model": "opencode/glm-5.3-flash", "variant": "low"},
    "advisor": {"mode": "subagent", "hidden": "true", "model": "openai/gpt-5.6-sol", "variant": "high"},
    "document": {"mode": "subagent", "hidden": "true", "model": "opencode/glm-5.3-flash"},
    "review": {"mode": "subagent", "hidden": "true", "model": "opencode/glm-5.3-flash"},
    "version": {"mode": "subagent", "hidden": "true", "model": "opencode/glm-5.3-flash"},
}
for name, expected in expectations.items():
    for key, value in expected.items():
        assert frontmatter[name].get(key) == value, (
            f"{name}: {key} must be {value}, got {frontmatter[name].get(key)!r}"
        )

# Subagents must not launch other agents.
for name in ("explore", "advisor", "document", "review", "version"):
    text = (agents_dir / f"{name}.md").read_text(encoding="utf-8")
    assert "task: deny" in text or "task:\n    " in text, name

# engineer: only the five specialists; architect: only explore; version: no publish.
engineer = (agents_dir / "engineer.md").read_text(encoding="utf-8")
for allowed in ("explore", "advisor", "document", "review", "version"):
    assert f"{allowed}: allow" in engineer, f"engineer must allow {allowed}"
architect = (agents_dir / "architect.md").read_text(encoding="utf-8")
assert "explore: allow" in architect

# architect: two-gate approval protocol (proposal -> accept -> persist -> ask).
for state in ("DRAFT", "REVISION_REQUESTED", "APPROVED", "PERSISTED", "HANDOFF"):
    assert state in architect, f"architect must define state {state}"
assert "Write ANY file while in `DRAFT`" in architect, (
    "architect must forbid writes before acceptance"
)
assert "¿Aceptas esta planificación?" in architect, (
    "architect must ask for plan acceptance"
)
assert "¿Deseas continuar ahora con la implementación" in architect, (
    "architect must ask before implementation"
)
assert "Tab" in architect, "architect must instruct the manual agent switch"
assert "usando Engineer" in architect, "architect must hand off to engineer"
assert "user action (Tab" in architect, (
    "architect must not claim it can switch agents itself"
)

# engineer: subagent failure policy (bounded retries, no advisor for transport failures).
assert "SUBAGENT FAILURE POLICY" in engineer
assert "DELEGATION MINIMUMS" in engineer
assert "expected file list" in engineer, (
    "engineer must pass the expected file list to version"
)

# architect: preserved permission map (roadmap-only edits, read-only git).
assert '"docs/roadmap/**": allow' in architect, (
    "architect must be limited to roadmap edits"
)
assert '"**/*.md": allow' not in architect, (
    "architect must not edit arbitrary markdown"
)
assert '"git status*": allow' in architect
for blocked in ("git push*", "git commit*", "git reset*"):
    assert f'"{blocked}"' not in architect or \
        f'"{blocked}": deny' in architect, f"architect must not allow {blocked}"
assert "explore: allow" in architect

# architect: roadmap index contract (mechanically resolvable active roadmap).
assert "docs/roadmap/INDEX.md" in architect, (
    "architect must maintain the roadmap index"
)
assert "INDEX.md" in engineer, "engineer must mark roadmaps DONE in the index"
for state in ("ACTIVE", "DONE", "BLOCKED", "SUPERSEDED"):
    assert state in architect, f"architect index states must include {state}"

# document: product docs only; planning and config boundaries are permission-enforced.
document = (agents_dir / "document.md").read_text(encoding="utf-8")
for blocked in ("**/docs/roadmap/**", "docs/roadmap/**", "AGENTS.md", "**/AGENTS.md", "**/.opencode/**"):
    assert f'"{blocked}": deny' in document, f"document must deny {blocked}"

version = (agents_dir / "version.md").read_text(encoding="utf-8")
for blocked in ("git push*", "git tag*", "git clean*", "git reset*", "git rebase*"):
    assert f'"{blocked}": deny' in version, f"version must deny {blocked}"
for blocked in ("git add .", "git add ./", "git add -A*", "git add --all*",
                "git commit --amend*", "git commit --no-verify*"):
    assert f'"{blocked}": deny' in version, f"version must deny {blocked}"
assert '"git commit*": allow' in version
assert '"git add*": allow' in version
# Ordering: specific denies must appear after the broad allows (last match wins).
assert version.index('"git add*": allow') < version.index('"git add -A*": deny')
assert version.index('"git commit*": allow') < version.index('"git commit --amend*": deny')
# version: explicit expected-file-list contract.
assert "expected file list" in version, (
    "version must require the expected file list from the invoker"
)
assert "--amend" in version and "--no-verify" in version

documents = [(root / "config.json", base)]

for path, payload in documents:
    for mcp in payload.get("mcp", {}).values():
        command = mcp.get("command", [])
        if command and command[0] == "uvx":
            assert len(command) > 1 and "==" in command[1], (
                f"{path}: uvx package must be pinned"
            )
        assert not any(value.endswith("@latest") for value in command), (
            f"{path}: latest package is not reproducible"
        )
PY

bash -n "$config_root/toolbox/wisemin-mysql-mcp"

if MYSQL_SSH_TARGET=unsupported \
  "$config_root/toolbox/wisemin-mysql-mcp" >/dev/null 2>&1; then
  fail "MySQL wrapper must reject unknown SSH targets"
fi

if grep -qF 'MonitoreoCenizas' "$config_root/toolbox/wisemin-mysql.yaml"; then
  fail "target-specific diagnostics must not live in the common MySQL config"
fi
grep -qF 'MonitoreoCenizas' "$config_root/toolbox/cenizas-diagnostics.yaml" || \
  fail "Cenizas diagnostics are missing"

if command -v yq >/dev/null 2>&1; then
  while IFS= read -r -d '' yaml_file; do
    yq eval-all 'true' "$yaml_file" >/dev/null
  done < <(find "$config_root/toolbox" -type f -name '*.yaml' -print0)
fi

if git -C "$repo_root" check-ignore -q "$relative_root/config.json"; then
  fail "config.json must be tracked"
fi
if git -C "$repo_root" check-ignore -q "$relative_root/.gitignore"; then
  fail ".gitignore must be tracked"
fi

for ignored in secrets/example.token skills/example/SKILL.md node_modules/example; do
  if ! git -C "$repo_root" check-ignore -q "$relative_root/$ignored"; then
    fail "$ignored must remain ignored"
  fi
done

if [[ -d "$config_root/secrets" ]]; then
  [[ "$(stat -c '%a' "$config_root/secrets")" == 700 ]] || \
    fail "secrets directory must use mode 0700"
  while IFS= read -r -d '' secret_file; do
    [[ "$(stat -c '%a' "$secret_file")" == 600 ]] || \
      fail "secret file must use mode 0600: $secret_file"
  done < <(find "$config_root/secrets" -type f -print0)
fi

if (( $(wc -l <"$config_root/AGENTS.md") > 30 )); then
  fail "global AGENTS.md should remain concise"
fi

[[ ! -e "$config_root/command/commit-diff.md" ]] || fail "commit-diff is obsolete"

printf 'OK\n'
