---
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git diff:*), Bash(git log:*)
description: Create a git commit
---

## Context

- Current git status: `git status`
- Current git diff (staged and unstaged changes): `git diff HEAD`
- Current branch: `git branch --show-current`
- Recent commits: `git log --oneline -10`

## Your task

Based on the above changes, create a single git commit accoding to the following rules.

- The message format should be `[commit type]: [summary of changes]`
- Select the following commit types
  - feat: New feature
  - fix: Bug fix or existing feature fix
  - docs: Docummentation
  - ci: CI/CD improvements
- Summary of changes to be written in English
- Omit phrases such as `Generated with` or `Co-Authored-By`
