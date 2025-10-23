# Infrastructure Setup

This directory contains infrastructure setup options for running Aptos chains for development and testing.

## Shared Resources

- **[Testing Guide](./testing-guide.md)** - Common testing and validation commands for both Docker and manual setups

## Setup Options

### 🐳 Docker Setup (Recommended)
**Easy, isolated, and reproducible**

- **Location**: [`setup-docker/`](./setup-docker/)
- **Best for**: Quick development, testing, CI/CD
- **Features**: Fresh start every time, no system dependencies
- **Platform**: Linux only (AMD64 architecture) - not compatible with Apple Silicon Macs
- **Documentation**: [`setup-docker/README.md`](./setup-docker/README.md)

### 🔧 Manual Setup (From Source)
**Full control and customization**

- **Location**: [`setup-from-source/`](./setup-from-source/)
- **Best for**: Custom configurations
- **Features**: Single validator, full control
- **Limitations**: Cannot run multi-chain (port conflicts), CLI funding issues
- **Documentation**: [`setup-from-source/README.md`](./setup-from-source/README.md)
