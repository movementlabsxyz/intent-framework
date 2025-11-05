# Claude Code Instructions

## Task Master AI Instructions
**Import Task Master's development workflow commands and guidelines, treat as if import is in the main CLAUDE.md file.**
@./.taskmaster/CLAUDE.md

## Commit Message Guidelines

**Keep commit messages concise and to the point.**

- Use conventional commit format: `type(scope): brief description`
- Do NOT add advertising or promotional text about Claude Code
- Do NOT add "Generated with Claude Code" footers
- Do NOT add "Co-Authored-By: Claude" lines
- Keep the message short and focused on what changed

Example:
```bash
# ✅ GOOD - concise and clear
git commit -m "feat(infra): convert Phase 5 test runners to Python"

# ❌ BAD - contains advertising
git commit -m "feat(infra): convert test runners

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

## File Path Handling

**ALWAYS use absolute paths when working with files in this project.**

- Determine the project root from git or working directory
- Use absolute paths in all tool calls (Read, Write, Edit, Bash, etc.)
- Never use relative paths - they cause errors when working directory changes
- This prevents errors from changing working directories

Example:
```bash
# ❌ BAD - relative path
python3 testing-infra/script.py

# ✅ GOOD - absolute path from project root
python3 /path/to/project-root/testing-infra/script.py
```
