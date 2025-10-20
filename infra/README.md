# Infrastructure Documentation

This directory contains infrastructure setup scripts and configurations for running Aptos nodes locally.

## Directory Structure

- `external/` - External dependencies (movement-aptos-core repository)
- `single-validator/` - Single local validator setup

## Key Generation Process

### Problem
The `aptos genesis set-validator-configuration` command expects a validator identity file with both private and public keys, but `aptos genesis generate-keys` creates separate files.

### Solution
We generate keys using `aptos genesis generate-keys` and then manually combine the private and public key information into the correct format.

### Process
1. Generate keys: `aptos genesis generate-keys --output-dir . --assume-yes`
2. This creates:
   - `private-keys.yaml` - Contains private keys
   - `public-keys.yaml` - Contains public keys and addresses
   - `validator-full-node-identity.yaml` - Full node identity
3. Manually create `validator-identity.yaml` by combining both files with the correct format:

```yaml
---
account_address: <from public-keys.yaml>
account_private_key: <from private-keys.yaml>
account_public_key: <from public-keys.yaml>
consensus_private_key: <from private-keys.yaml>
consensus_public_key: <from public-keys.yaml>
consensus_proof_of_possession: <from public-keys.yaml>
full_node_network_private_key: <from private-keys.yaml>
full_node_network_public_key: <from public-keys.yaml>
validator_network_private_key: <from private-keys.yaml>
validator_network_public_key: <from public-keys.yaml>
```

### File Locations
All validator files are stored in `infra/single-validator/work/`:
- `validator-identity.yaml` - Combined validator identity (used by aptos genesis set-validator-configuration)
- `private-keys.yaml` - Private keys only
- `public-keys.yaml` - Public keys and addresses
- `validator-full-node-identity.yaml` - Full node identity
- `data/` - Directory for genesis files and validator data

### Security Note
These are test keys for local development only. Never commit real validator keys to version control.
