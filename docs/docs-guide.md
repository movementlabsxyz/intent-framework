# Documentation Guide

This guide explains how the Intent Framework documentation is organized and how to navigate it.

## Documentation Structure

The documentation is organized into two levels:

### Component READMEs

Each component directory (e.g., `move-intent-framework/`, `trusted-verifier/`) contains a README with:

- **Brief description** of the component
- **Quick Start** section with essential commands to get started
- **Link to full documentation** in `docs/`

These READMEs are designed for developers working directly in a component directory who need immediate access to quick start instructions.

### Consolidated Documentation

All comprehensive documentation is located in `docs/` with component subfolders. Each component has a corresponding folder in `docs/` (e.g., `docs/component-name/`) that contains:

- **README.md** - Overview and links to all documentation for that component
- **Specialized guides** - Detailed documentation on specific topics (API references, technical overviews, etc.)

## Where to Find Information

### Quick Start / Getting Started

- **Component READMEs** (`component-name/README.md`) - Quick start commands and setup instructions
- **Docs READMEs** (`docs/component-name/README.md`) - Reference to component README for quick start

### Detailed Documentation

- **Component docs folders** (`docs/component-name/`) - All detailed guides, API references, and technical documentation

### Cross-Component Information

- **Root docs README** (`docs/README.md`) - Overview and links to all components
- **System-wide documentation** - Cross-cutting documentation files in `docs/`

## Documentation Philosophy

1. **Quick Start in Components**: Essential commands and setup live in component READMEs for immediate access
2. **Full Docs in `docs/`**: Comprehensive documentation is consolidated in `docs/` for easy discovery
3. **No Duplication**: Component READMEs link to docs rather than duplicating content
4. **Single Source of Truth**: Detailed information lives in `docs/`, component READMEs are entry points

## Navigation Tips

- **New to a component?** Start with the component README (`component-name/README.md`) for quick start
- **Need detailed information?** Go to `docs/component-name/README.md` for the full documentation index
- **Looking for specific topics?** Check the specialized guides in `docs/component-name/`
- **Understanding the system?** Start with `docs/README.md` for an overview of all components
