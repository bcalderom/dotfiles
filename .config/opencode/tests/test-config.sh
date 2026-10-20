#!/usr/bin/env bash
set -euo pipefail

script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"
script_dir="$(cd -- "$(dirname -- "$script_path")" && pwd -P)"
config_root="$(dirname -- "$script_dir")"
repo_root="$(git -C "$config_root" rev-parse --show-toplevel)"
readonly script_path script_dir config_root repo_root
readonly relative_root="${config_root#"$repo_root"/}"
[[ $# -le 1 && ( $# -eq 0 || "$1" == --runtime ) ]] || { echo 'Usage: test-config.sh [--runtime]' >&2; exit 2; }
command -v yq >/dev/null 2>&1 || { echo 'go-yq is required to parse agent frontmatter' >&2; exit 1; }
export OPENCODE_CONFIG_RUNTIME_CHECK="${1:-}"

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
import fnmatch
import os
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
required = set(sys.argv[2:9])
removed = set(sys.argv[9:11])

base = json.loads((root / "opencode.json").read_text(encoding="utf-8"))

assert base["share"] == "disabled"
assert base["update"] == "notify"
assert base["agents"]["title"]["model"] == "openai/gpt-5.5"
assert base["experimental"]["subagent_depth"] == 1
assert base["compaction"] == {"auto": True, "keep": {"tokens": 15000}, "buffer": 10000}
assert not ({"autoupdate", "small_model", "subagent_depth", "agent", "permission", "tools"} & base.keys())
assert len(base["mcp"]["servers"]) == 3
assert {
    name for name, mcp in base["mcp"]["servers"].items() if not mcp.get("disabled", False)
} == {"context7", "jcodemunch"}
assert base["mcp"]["servers"]["context7"]["oauth"] is False
assert all(base["mcp"]["servers"][name]["codemode"] for name in ("context7", "jcodemunch"))

# explore is defined as a file agent, not in opencode.json.
assert "explore" not in base.get("agents", {}), (
    "explore must be defined in agent/explore.md only"
)

def effect(rules, action, resource="*"):
    result = "ask"
    for rule in rules:
        if fnmatch.fnmatchcase(action, rule["action"]) and fnmatch.fnmatchcase(resource, rule["resource"]):
            result = rule["effect"]
    return result

assert effect(base["agents"]["general"]["permissions"], "subagent", "review") == "deny"
assert effect(base["permissions"], "external_directory", "/external/*") == "ask"

agents_dir = root / "agent"
present = {p.stem for p in agents_dir.glob("*.md")}
assert required <= present, f"missing agents: {sorted(required - present)}"
assert not (present & removed), f"agents must be removed: {sorted(present & removed)}"

# Parse real YAML, not line fragments: ordering and wildcard behavior matter.
frontmatter = {}
for name in required:
    text = (agents_dir / f"{name}.md").read_text(encoding="utf-8")
    header = text.split("---", 2)[1]
    parsed = subprocess.run(["yq", "eval", "-o=json", ".", "-"], input=header,
                            text=True, capture_output=True, check=True)
    frontmatter[name] = json.loads(parsed.stdout)
    assert not ({"permission", "variant", "tools", "prompt", "maxSteps"} & frontmatter[name].keys()), name
    assert re.fullmatch(r"#[0-9a-fA-F]{6}", frontmatter[name]["color"]), name

expectations = {
    "architect": {"mode": "primary", "model": "openai/gpt-5.6-sol#medium"},
    "engineer": {"mode": "primary", "model": "openai/gpt-5.6-luna#medium"},
    "explore": {"mode": "subagent", "hidden": True, "model": "openai/gpt-5.6-luna#low"},
    "advisor": {"mode": "subagent", "hidden": True, "model": "openai/gpt-5.6-sol#high"},
    "document": {"mode": "subagent", "hidden": True, "model": "openai/gpt-5.6-luna#low"},
    "review": {"mode": "subagent", "hidden": True, "model": "openai/gpt-5.6-luna#medium"},
    "version": {"mode": "subagent", "hidden": True, "model": "openai/gpt-5.6-luna#low"},
}
for name, expected in expectations.items():
    for key, value in expected.items():
        assert frontmatter[name].get(key) == value, (
            f"{name}: {key} must be {value}, got {frontmatter[name].get(key)!r}"
        )

def rules(name):
    defaults = [{"action": "*", "resource": "*", "effect": "allow"},
                {"action": "read", "resource": "*.env", "effect": "ask"},
                {"action": "read", "resource": "*.env.*", "effect": "ask"},
                {"action": "read", "resource": "*.env.example", "effect": "allow"}]
    return defaults + base["permissions"] + frontmatter[name]["permissions"]

for name in required:
    assert effect(rules(name), "read", "nested/.env") == "ask", name
    assert effect(rules(name), "read", "nested/.env.production") == "ask", name
    assert effect(rules(name), "read", "nested/.env.example") == "allow", name

# Evaluate safe commands as strings only; never execute Git mutations in tests.
for name in ("explore", "advisor", "document", "review", "version"):
    assert effect(rules(name), "subagent", "general") == "deny", name
    assert effect(rules(name), "private_mcp_mutate") == "deny", name
    assert effect(rules(name), "external_directory", "/external/*") == "ask", name
for name in ("architect", "advisor", "review", "document", "version"):
    assert effect(rules(name), "execute") == "deny", name
    assert effect(rules(name), "context7_query-docs") == "deny", name
    assert effect(rules(name), "jcodemunch_order") == "deny", name
for name in ("advisor", "review", "version", "explore"):
    assert effect(rules(name), "edit", "src/main.py") == "deny", name
assert effect(rules("explore"), "execute") == "allow"
for action in ("jcodemunch_route", "jcodemunch_menu", "jcodemunch_order"):
    assert effect(rules("explore"), action) == "allow", action
for action in ("jcodemunch_index_folder", "context7_query-docs", "webfetch", "shell"):
    assert effect(rules("explore"), action) == "deny", action

# engineer: only the five specialists; architect: only explore; version: no publish.
engineer = (agents_dir / "engineer.md").read_text(encoding="utf-8")
for allowed in ("explore", "advisor", "document", "review", "version"):
    assert effect(rules("engineer"), "subagent", allowed) == "allow", allowed
assert effect(rules("engineer"), "subagent", "general") == "deny"
architect = (agents_dir / "architect.md").read_text(encoding="utf-8")
assert effect(rules("architect"), "subagent", "explore") == "allow"
assert effect(rules("architect"), "subagent", "advisor") == "deny"

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

assert "## SESSION CHECKLIST" in engineer
assert "Markdown checklist" in engineer
assert "todowrite" not in engineer and "task_id" not in engineer and "`task`" not in engineer
assert "`sessionID`" in engineer and "`subagent`" in engineer
assert engineer.index("6. ROADMAP STATE:") < engineer.index("7. VERSION:")
assert "without further file edits" in engineer
assert "ONLY the work of the current session/increment" in engineer
assert "Exactly ONE item `in_progress` at a time" in engineer

# engineer: final report contract (native Markdown, four sections, no global text fence).
for heading in ("## Resultado", "## Cambios realizados", "## Evidencia", "## Próximo paso"):
    assert heading in engineer, f"engineer report must contain {heading}"
for token in ("DONE", "BLOCKED", "PASS", "CHANGES_REQUIRED", "VERSION_BLOCKED"):
    assert token in engineer, f"engineer report tokens must include {token}"
report = engineer.split("## REPORT (always end with)", 1)[1]
assert not report.lstrip().startswith("```text"), (
    "engineer report must not be wrapped in a global ```text fence"
)

# architect: preserved permission map (roadmap-only edits, read-only git).
for path in ("docs/roadmap/001.md", "/workspace/project/docs/roadmap/INDEX.md"):
    assert effect(rules("architect"), "edit", path) == "allow", path
for path in ("README.md", "src/main.py", ".opencode/agents/example.md"):
    assert effect(rules("architect"), "edit", path) == "deny", path
assert effect(rules("architect"), "shell", "git status --short") == "allow"
for command in ("git push origin", "git commit -m test", "git reset --soft HEAD"):
    assert effect(rules("architect"), "shell", command) == "deny", command

# architect: roadmap index contract (mechanically resolvable active roadmap).
assert "docs/roadmap/INDEX.md" in architect, (
    "architect must maintain the roadmap index"
)
assert "INDEX.md" in engineer, "engineer must mark roadmaps DONE in the index"
for state in ("ACTIVE", "DONE", "BLOCKED", "SUPERSEDED"):
    assert state in architect, f"architect index states must include {state}"

# document: product docs only; planning and config boundaries are permission-enforced.
document = (agents_dir / "document.md").read_text(encoding="utf-8")
assert effect(rules("document"), "edit", "docs/guide.md") == "allow"
for blocked in ("docs/roadmap/INDEX.md", "AGENTS.md", "nested/AGENTS.md", ".opencode/agents/review.md",
                "nested/.opencode/agents/review.md", ".config/opencode/agent/review.md"):
    assert effect(rules("document"), "edit", blocked) == "deny", blocked

version = (agents_dir / "version.md").read_text(encoding="utf-8")
for command in ("git push origin", "git tag test", "git clean -n", "git reset --soft HEAD", "git rebase main",
                "git add .", "git add ./", "git add -A", "git add --all", "git commit --amend", "git commit --no-verify"):
    assert effect(rules("version"), "shell", command) == "deny", command
for command in ("git status --short", "git add -- README.md", "git commit -m test"):
    assert effect(rules("version"), "shell", command) == "allow", command
# version: explicit expected-file-list contract.
assert "expected file list" in version, (
    "version must require the expected file list from the invoker"
)
assert "--amend" in version and "--no-verify" in version

example = json.loads((root / "config.local.example.json").read_text())
documents = [(root / "opencode.json", base), (root / "config.local.example.json", example)]
local_path = root / "config.local.json"
if local_path.exists():
    local = json.loads(local_path.read_text())
    assert not ({"agent", "permission", "autoupdate", "small_model", "subagent_depth"} & local.keys())
    assert not any(key != "$schema" and key != "mcp" and value == base.get(key)
                   for key, value in local.items()), "private overlay must not duplicate public defaults"
    assert not (local.get("mcp", {}).get("servers", {}).keys() & base["mcp"]["servers"].keys()), \
        "public MCP definitions belong in the base, not the private overlay"
    assert local_path.stat().st_mode & 0o777 == 0o600, "private overlay must use mode 600"
    documents.append((local_path, local))

for path, payload in documents:
    assert set(payload.get("mcp", {})) <= {"servers", "timeout"}, "native v2 mcp.servers required"
    for mcp in payload.get("mcp", {}).get("servers", {}).values():
        assert "enabled" not in mcp
        assert not isinstance(mcp.get("timeout"), int)
        command = mcp.get("command", [])
        if command and command[0] == "uvx":
            package = command[2] if len(command) > 2 and command[1] == "--from" else command[1] if len(command) > 1 else ""
            assert "==" in package, (
                f"{path}: uvx package must be pinned"
            )
        assert not any(value.endswith("@latest") for value in command), (
            f"{path}: latest package is not reproducible"
        )

if os.environ.get("OPENCODE_CONFIG_RUNTIME_CHECK") == "--runtime":
    # Introspect definitions only: no model generation, reload or tool execution.
    sources = subprocess.run(["opencode", "debug", "config"], text=True, capture_output=True, check=True, timeout=60)
    loaded = next(source["info"] for source in json.loads(sources.stdout)
                  if source.get("type") == "document" and Path(source["path"]).resolve() == (root / "opencode.json").resolve())
    assert loaded["experimental"]["subagent_depth"] == 1
    assert loaded["compaction"] == base["compaction"]
    assert loaded["permissions"] == base["permissions"]
    assert set(loaded["mcp"]["servers"]) == set(base["mcp"]["servers"])
    parsed = subprocess.run(["opencode", "debug", "agents"], text=True, capture_output=True, check=True, timeout=60)
    actual = {agent["id"]: agent for agent in json.loads(parsed.stdout)}
    for name, meta in frontmatter.items():
        agent = actual[name]
        model, variant = meta["model"].split("#")
        provider, model_id = model.split("/", 1)
        assert agent["model"] == {"id": model_id, "providerID": provider, "variant": variant}, name
        assert agent["mode"] == meta["mode"] and agent["hidden"] == meta.get("hidden", False), name
        assert agent["color"] == meta["color"], name
        configured = meta["permissions"]
        # The runtime may append protective rules (for example browser denial).
        assert any(agent["permissions"][index:index + len(configured)] == configured
                   for index in range(len(agent["permissions"]))), name
        probes = [(action, "*") for action in ("edit", "execute", "private_mcp_mutate", "subagent")]
        probes += [("read", ".env"), ("read", ".env.example"), ("read", "src/main.py"),
                   ("edit", "docs/roadmap/INDEX.md"), ("edit", ".opencode/agents/example.md"),
                   ("shell", "git commit -m test"), ("shell", "git push origin"),
                   ("subagent", "explore"), ("subagent", "review"), ("subagent", "general"),
                   ("external_directory", "/external/*"), ("jcodemunch_order", "*")]
        for action, resource in probes:
            assert effect(agent["permissions"], action, resource) == effect(rules(name), action, resource), (name, action, resource)
    print("Runtime OpenCode v2 agent loading and ordered permissions: OK")
PY

if command -v yq >/dev/null 2>&1; then
  while IFS= read -r -d '' yaml_file; do
    yq eval-all 'true' "$yaml_file" >/dev/null
  done < <(find "$config_root/toolbox/examples" -type f -name '*.yaml' -print0)
fi

if [[ -f "$config_root/config.local.json" ]]; then
  python3 -m json.tool "$config_root/config.local.json" >/dev/null
fi
if [[ -d "$config_root/toolbox/local" ]]; then
  while IFS= read -r -d '' local_script; do
    bash -n "$local_script"
  done < <(find "$config_root/toolbox/local" -type f -perm -0100 -print0)
fi

if git -C "$repo_root" check-ignore -q "$relative_root/opencode.json"; then
  fail "opencode.json must be tracked"
fi
if git -C "$repo_root" check-ignore -q "$relative_root/.gitignore"; then
  fail ".gitignore must be tracked"
fi

for ignored in config.local.json config.local.jsonc cli.json service.json config.local.json.backup toolbox/local/example secrets/example.token skills/example/SKILL.md node_modules/example; do
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
