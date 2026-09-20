# Global OpenCode Instructions

- Inspect the relevant files and repository guidance before changing anything.
- Follow the nearest project `AGENTS.md`; project instructions override these defaults.
- Make the smallest change that fully addresses the request.
- Do not modify or revert unrelated worktree changes.
- Before patching, read every target file and use exact anchors. Split large
  multi-file patches; after a failure, re-read and retry only the failed file.
- Do not read, expose, copy, or commit secrets unless the user explicitly requires
  access to a specific credential.
- Never execute destructive commands or stop an existing service without explicit
  approval. Prefer isolated ports when a test needs a local service.
- Use external documentation only when it is needed. Never send proprietary code,
  logs, credentials, customer data, or infrastructure details to documentation
  services.
- Run the repository's relevant configured checks after non-trivial changes. Report
  exact commands and failures instead of bypassing them.
- Do not add dependencies, global tools, or new architectural patterns without a
  concrete need.
- Commit, amend, push, publish, or create pull requests only when explicitly asked.
- Before a requested commit, inspect status, staged changes, and recent history;
  never include secrets or unrelated files and never bypass hooks.
- Exception: the `version` subagent may create local commits automatically after
  a review PASS; it must never push, tag, or run destructive git operations.
