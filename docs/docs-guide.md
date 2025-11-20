# Documentation Guide

This guide explains how the Intent Framework documentation is organized and how to navigate it.

## Documentation Structure

The documentation uses a three-layer structure:

### Layer 1: Component READMEs

Each component directory (e.g., `move-intent-framework/`, `trusted-verifier/`) contains a README for navigation from code:

- Brief description
- Quick start commands
- Link to full documentation

### Layer 2: Docs READMEs

Each component has a corresponding folder in `docs/` (e.g., `docs/component-name/`) with:

- **README.md** - Overview and documentation index
- **Specialized guides** - Detailed documentation on specific topics

### Layer 3: Specialized Guides

Specialized guides in `docs/component-name/` cover specific implementation topics:

- API references
- Technical overviews
- Detailed usage patterns

## Where to Find Information

- **Quick start**: Component READMEs (`component-name/README.md`)
- **Implementation overview**: Docs READMEs (`docs/component-name/README.md`)
- **Detailed implementation**: Specialized guides in `docs/component-name/`
- **System overview**: `docs/README.md`
- **Cross-cutting topics**: Files in `docs/` root (e.g., `protocol.md`)
- **Design rationale**: `.taskmaster/docs/` (internal architecture documentation)

## Documentation Philosophy

1. **Navigation layer** (Component READMEs): Quick access from code
2. **Implementation layer** (Docs READMEs + Specialized guides): How the code works
3. **Design layer** (`.taskmaster/docs/`): Why we develop this way - architecture rationale
4. **No duplication**: Each layer serves a distinct purpose
