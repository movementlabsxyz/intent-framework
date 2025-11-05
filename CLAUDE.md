# Claude Code Instructions

## Task Master AI Instructions
**Import Task Master's development workflow commands and guidelines, treat as if import is in the main CLAUDE.md file.**
@./.taskmaster/CLAUDE.md

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
