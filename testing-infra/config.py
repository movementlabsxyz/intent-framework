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

