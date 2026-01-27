---
description: Run git commit
agent: build
model: openai/gpt-5.2
---

1. Execute `git diff --cached` to view only the staged changes.
2. Read the output and analyze what files, functions, or logic were added, removed, or modified.
3. Based on the changes, generate a clear, detailed, and meaningful **conventional commit** message. Use the format:
   `type(scope): summary`

* **type**: Choose from `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `style`, etc.
* **scope**: Name the module, feature, or component impacted.
* **summary**: A concise description (max 72 characters).

4. Add an optional detailed body (wrapped at 72 chars per line) if needed.
5. Use `git commit -m` to apply the commit message.
6. Do not include unstaged or untracked changes.
   Return only the final commit message and confirmation of the commit.

