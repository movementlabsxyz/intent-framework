#!/usr/bin/env python3
"""
Configuration management for E2E tests.

This module provides the TestConfig dataclass that gets populated
as tests progress and is passed between scripts.
"""

import pickle
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass
class TestConfig:
    """
    Configuration object that gets populated as tests progress.
    
    This config is passed between scripts using pickle serialization.
    Values are populated incrementally as the test flow progresses.
    """
    
    # Chain addresses
    chain1_address: Optional[str] = None  # Aptos hub chain module address
    chain2_address: Optional[str] = None  # Aptos connected chain (for Aptos tests)
    
    # Account addresses
    alice_chain1_address: Optional[str] = None
    bob_chain1_address: Optional[str] = None
    
    # EVM addresses
    vault_address: Optional[str] = None  # IntentVault contract address
    verifier_address: Optional[str] = None  # EVM verifier address
    
    # Intent IDs (generated during submission)
    intent_id: Optional[str] = None  # Generated intent ID
    intent_id_evm: Optional[str] = None  # EVM-formatted intent ID
    
    # Config paths
    verifier_config_path: Optional[Path] = None
    
    # Flags
    setup_chains: bool = False
    
    def validate_required(self, required_fields: list[str]) -> list[str]:
        """
        Validate that required fields are set.
        
        Args:
            required_fields: List of field names that must be set
            
        Returns:
            List of missing field names
        """
        missing = []
        for field_name in required_fields:
            if getattr(self, field_name) is None:
                missing.append(field_name)
        return missing
    
    def save(self, path: Path) -> None:
        """
        Save config to file using pickle.
        
        Args:
            path: Path where config should be saved
        """
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, 'wb') as f:
            pickle.dump(self, f)
    
    @classmethod
    def load(cls, path: Path) -> 'TestConfig':
        """
        Load config from pickle file.
        
        Args:
            path: Path to config file
            
        Returns:
            TestConfig instance
        """
        with open(path, 'rb') as f:
            return pickle.load(f)


def get_config_path() -> Path:
    """
    Get the standard config file path.
    
    Returns:
        Path to the test config file
    """
    # Import here to avoid circular dependency
    from pathlib import Path
    
    # Try to get PROJECT_ROOT from common if available
    try:
        import common
        if common.PROJECT_ROOT:
            return common.PROJECT_ROOT / "tmp" / "test-config.pkl"
    except (ImportError, AttributeError):
        pass
    
    # Fallback: assume we're in testing-infra directory
    # Go up to project root
    current = Path(__file__).parent
    if current.name == "testing-infra":
        project_root = current.parent
    else:
        # Assume we're already at project root
        project_root = current
    
    return project_root / "tmp" / "test-config.pkl"


def cleanup_old_config(config_path: Path = None, log_fn=None) -> None:
    """
    Delete any existing config file to ensure a fresh start.
    
    Args:
        config_path: Path to config file (defaults to standard location)
        log_fn: Optional logging function to call with message
    """
    if config_path is None:
        config_path = get_config_path()
    
    if config_path.exists():
        if log_fn:
            log_fn(f"   Deleting old config file: {config_path}")
        config_path.unlink()


def setup_config_file(config_path: Path = None, log_fn=None) -> Path:
    """
    Set up the config file for a fresh test run.
    
    This function:
    1. Gets the standard config file path
    2. Deletes any existing config file to ensure a fresh start
    
    Args:
        config_path: Path to config file (defaults to standard location)
        log_fn: Optional logging function to call with messages
        
    Returns:
        Path to the config file
    """
    if config_path is None:
        config_path = get_config_path()
    
    cleanup_old_config(config_path, log_fn)
    
    return config_path


def print_config_content(config: TestConfig, log_fn=None) -> None:
    """
    Print all config fields for debugging.
    
    Args:
        config: TestConfig instance to print
        log_fn: Optional logging function (defaults to print)
    """
    if log_fn is None:
        log_fn = print
    
    log_fn("📋 Config file content:")
    log_fn("   Chain addresses:")
    log_fn(f"      chain1_address: {config.chain1_address}")
    log_fn(f"      chain2_address: {config.chain2_address}")
    log_fn("   Account addresses:")
    log_fn(f"      alice_chain1_address: {config.alice_chain1_address}")
    log_fn(f"      bob_chain1_address: {config.bob_chain1_address}")
    log_fn("   EVM addresses:")
    log_fn(f"      vault_address: {config.vault_address}")
    log_fn(f"      verifier_address: {config.verifier_address}")
    log_fn("   Intent IDs:")
    log_fn(f"      intent_id: {config.intent_id}")
    log_fn(f"      intent_id_evm: {config.intent_id_evm}")
    log_fn("   Other:")
    log_fn(f"      verifier_config_path: {config.verifier_config_path}")
    log_fn(f"      setup_chains: {config.setup_chains}")

