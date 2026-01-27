## ✅ Pre-Task Checklist

Before initiating any action (feature, fix, refactor), agents **must** perform the following:

- **Evaluate the Impact of Changes**:
   - Does this change introduce new patterns, dependencies, or duplicated logic?
   - If **yes**, halt and escalate for clarification before continuing.

- **Docs / External Context**:
   - When you need external documentation or library/API reference material, auto-invoke Context7 by including `use context7` in your prompt.

- **Git Hygiene / .gitignore**:
   - If the repo root has no `.gitignore`, generate one using a standard template based on detected language(s) (default to Python when unclear).
   - Never overwrite an existing `.gitignore` automatically (only create when missing; append only when explicitly requested).
   - Always include ignores for secrets/local config (`.env*`, `*.key`, `*.pem`, `credentials*.json`, etc.).

- **Quality Gates**:
   - Identify the project's existing `lint`/`format`/`test`/`build` commands (scripts/Makefile/task runner/CI) and run the relevant ones before finishing.
   - If the repo has no established commands, call it out explicitly and propose the lightest-weight addition (avoid adding new tooling unless necessary).

---

## 🧠 Core Principles & Engineering Conduct

### 🧱 Design & Architecture

- Choose **simple, proven solutions**.
- Avoid introducing new technologies or architectural patterns unless:
  - Existing ones are inadequate **and**
  - A migration or deprecation path is in place.
- Eliminate or consolidate duplicate logic.

### 🎯 Scope Discipline

- Only modify code directly related to the task at hand.
- Avoid unsolicited formatting changes or "helpful" side-edits.
- Think through ripple effects across the codebase.

### 🧼 Code Hygiene

- Ensure code is clean, modular, and readable.
- Only remove unused code if it's **within scope**.
- Enforce a **300-line maximum per file** — refactor as needed.
- Avoid throwaway scripts; prioritize reusable utilities.

### 🧬 Data Integrity & Duplication

- Always check for existing functionality before writing new logic.
- **Never mock or stub data** in development or production environments.
- Mocking/stubbing is strictly allowed in test contexts only.

### 🛑 Runtime Safety

- Before starting local servers in tests, ensure all related services or ports are stopped to avoid conflicts.

---

## 🧪 Testing Standards

- Provide full test coverage for **non-trivial** code changes.
- Focus on **behavioral outcomes**, not internal implementation details.
- Never skip writing tests for “small” or “obvious” updates.

### What Counts As Non-Trivial

- New user-facing behavior, new flags/config, new integration points, concurrency/IO changes, data migrations, or any bug fix.

### Testing Expectations

- **Bug fixes**: add a regression test that fails before the fix and passes after.
- **Features**: add behavior tests at the closest stable boundary (public API/CLI entrypoint/module interface).
- **Refactors**: keep behavior stable; add characterization tests first if behavior is unclear.
- **Determinism**: avoid time/network/flaky dependencies unless the test is explicitly integration/e2e.
- **Mocking**: mocks/stubs are allowed in tests; do not fake/stub real data sources in development/production code.

---

## 📝 Documentation Standards

- Update docs in the same change-set when behavior changes.
- New config/env vars must be documented with names, purpose, defaults, and an example (never include real secrets).
- For notable design decisions or tradeoffs, add a short ADR when the repo already uses ADRs; otherwise document in the PR/commit body.

---

## 🧾 Development Workflow

- **Definition of Done** (for non-trivial changes):
  - tests pass locally (or provide exact failing command + failure reason)
  - lint/format passes when configured
  - build passes when applicable
  - docs updated when applicable
  - no secrets committed; new sensitive files are ignored
- Keep changes small and reviewable; split large work into steps/commits.

---

## 🌿 Git & Conventional Commits

- Use Conventional Commits (imperative, <= 72 chars):
  - `feat(scope): ...`, `fix(scope): ...`, `docs(scope): ...`, `test(scope): ...`, `refactor(scope): ...`, `chore(scope): ...`, `ci(scope): ...`
- One logical change per commit; avoid mixing refactors with behavior changes.
- Prefer descriptive bodies that explain *why* (constraints, tradeoffs, user impact).
- Breaking changes must be explicit with `BREAKING CHANGE: ...`.
- Never commit secrets (`.env*`, tokens, private keys); use example files (`.env.example`) and docs.

---

## 🧠 Agent Mindset

Agents are expected to:

- Prioritize **understanding** over execution.
- Communicate uncertainty or architectural concerns **before acting**.
- Apply existing project conventions **consistently**.
- Think like a long-term maintainer, not a one-off contributor.

---

## ⚠️ Compliance & Enforcement

- Agents that act outside these guidelines may be paused or terminated within a session.
- Repeated violations may result in a session-wide reset or manual override by maintainers.
