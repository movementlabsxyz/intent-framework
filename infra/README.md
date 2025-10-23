# Infrastructure Setup

This directory contains infrastructure setup options for running Aptos chains for development and testing.

## Shared Resources

- **[Testing Guide](./testing-guide.md)** - Common testing and validation commands for both Docker and manual setups

## Setup Options

### 🐳 Docker Setup 
**Easy, isolated, and reproducible**

⚠️ **Warning**: This script does not work on Apple Silicon Macs (M1/M2) - Linux AMD64 architecture only

- **Location**: [`setup-docker/`](./setup-docker/)
- **Best for**: Quick development, testing, CI/CD, cross-chain testing
- **Features**: Fresh start every time, no system dependencies, dual-chain support
- **Platform**: Linux only (AMD64 architecture) - not compatible with Apple Silicon Macs
- **Documentation**: [`setup-docker/README.md`](./setup-docker/README.md)
- **Testing**: [`test-alice-bob.sh`](./setup-docker/test-alice-bob.sh) - Complete Alice and Bob account testing
- **Dual Chain**: [`setup-dual-chains.sh`](./setup-docker/setup-dual-chains.sh) - Two independent chains for cross-chain testing
- **Stop Dual Chain**: [`stop-dual-chains.sh`](./setup-docker/stop-dual-chains.sh) - Clean shutdown for both chains

### 🔧 Manual Setup (From Source)
**Full control and customization**

⚠️ **Warning**: Cannot run multi-chain setup (port conflicts) - use Docker for dual-chain testing

- **Location**: [`setup-from-source/`](./setup-from-source/)
- **Best for**: Custom configurations
- **Features**: Single validator, full control
- **Limitations**: Cannot run multi-chain (port conflicts), CLI funding issues
- **Documentation**: [`setup-from-source/README.md`](./setup-from-source/README.md)
