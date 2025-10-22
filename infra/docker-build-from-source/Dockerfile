# Multi-stage Dockerfile for Aptos Node
# Stage 1: Build the binaries
FROM ubuntu:22.04 as builder

# Set environment variables for non-interactive installation
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    curl \
    libssl-dev \
    pkg-config \
    build-essential \
    git \
    libudev-dev \
    libusb-1.0-0-dev \
    clang \
    libclang-dev \
    libdw-dev \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && . $HOME/.cargo/env \
    && rustup install 1.89.0 \
    && rustup default 1.89.0 \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /aptos

# Copy the Aptos source code
COPY ../external/aptos-core /aptos/aptos-core

# Build the Aptos binaries with memory optimization
RUN cd /aptos/aptos-core \
    && . $HOME/.cargo/env \
    && cargo build --release --bin aptos-node --bin aptos-faucet-service -j 1

# Stage 2: Runtime image
FROM ubuntu:22.04

# Set environment variables for non-interactive installation
ENV DEBIAN_FRONTEND=noninteractive

# Install only runtime dependencies
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /aptos

# Copy binaries from builder stage
COPY --from=builder /aptos/aptos-core/target/release/aptos-node /usr/local/bin/
COPY --from=builder /aptos/aptos-core/target/release/aptos-faucet-service /usr/local/bin/

# Make binaries executable
RUN chmod +x /usr/local/bin/aptos-node /usr/local/bin/aptos-faucet-service

# Create directories for node data
RUN mkdir -p /aptos/data /aptos/config

# Expose default Aptos ports
EXPOSE 8080 8081

# Default command
CMD ["aptos-node", "--help"]