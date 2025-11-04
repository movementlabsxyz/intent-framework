// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title IntentVault
 * @notice Vault that holds funds and releases them to solvers when verifier signature checks out
 * @dev Based on Solana vault pattern with ECDSA signature verification
 */
contract IntentVault {
    using SafeERC20 for IERC20;

    /// @notice Authorized verifier address that can approve releases
    address public immutable verifier;

    /// @notice Vault data structure
    struct Vault {
        address maker;           // User who deposited funds
        address token;           // ERC20 token address
        uint256 amount;          // Amount deposited
        bool isClaimed;          // Whether funds have been claimed
        uint256 expiry;          // Expiry timestamp (optional, enforced off-chain)
    }

    /// @notice Mapping from intent ID to vault data
    mapping(uint256 => Vault) public vaults;

    /// @notice Events
    event VaultInitialized(uint256 indexed intentId, address indexed vault, address indexed maker, address token);
    event DepositMade(uint256 indexed intentId, address indexed user, uint256 amount, uint256 total);
    event VaultClaimed(uint256 indexed intentId, address indexed solver, uint256 amount);
    event VaultCancelled(uint256 indexed intentId, address indexed maker, uint256 amount);

    /// @notice Errors
    error VaultAlreadyClaimed();
    error NoDeposit();
    error UnauthorizedMaker();
    error InvalidSignature();
    error InvalidApprovalValue();
    error UnauthorizedVerifier();

    /**
     * @notice Initialize the vault with verifier address
     * @param _verifier Address of the authorized verifier
     */
    constructor(address _verifier) {
        require(_verifier != address(0), "Invalid verifier address");
        verifier = _verifier;
    }

    /**
     * @notice Initialize a new vault for a specific intent
     * @param intentId Unique intent identifier
     * @param token ERC20 token address to be deposited (use address(0) for ETH)
     * @param expiry Expiry timestamp (can be 0 for no expiry)
     */
    function initializeVault(
        uint256 intentId,
        address token,
        uint256 expiry
    ) external {
        require(vaults[intentId].maker == address(0), "Vault already initialized");

        vaults[intentId] = Vault({
            maker: msg.sender,
            token: token,
            amount: 0,
            isClaimed: false,
            expiry: expiry
        });

        emit VaultInitialized(intentId, address(this), msg.sender, token);
    }

    /**
     * @notice Deposit tokens or ETH into vault
     * @param intentId Intent identifier
     * @param amount Amount of tokens/ETH to deposit
     */
    function deposit(uint256 intentId, uint256 amount) external payable {
        Vault storage vault = vaults[intentId];
        
        require(vault.maker != address(0), "Vault not initialized");
        if (vault.isClaimed) revert VaultAlreadyClaimed();
        
        require(amount > 0, "Amount must be greater than 0");
        
        if (vault.token == address(0)) {
            // ETH deposit
            require(msg.value == amount, "ETH amount mismatch");
            vault.amount += amount;
        } else {
            // ERC20 token deposit
            require(msg.value == 0, "ETH not accepted for token vault");
            IERC20(vault.token).safeTransferFrom(msg.sender, address(this), amount);
            vault.amount += amount;
        }
        
        emit DepositMade(intentId, msg.sender, amount, vault.amount);
    }

    /**
     * @notice Claim vault funds (solver only, requires verifier signature)
     * @param intentId Intent identifier
     * @param approvalValue Approval value (must be 1 to approve)
     * @param signature Verifier's ECDSA signature over keccak256(abi.encodePacked(intentId, approvalValue))
     */
    function claim(
        uint256 intentId,
        uint8 approvalValue,
        bytes memory signature
    ) external {
        Vault storage vault = vaults[intentId];
        
        if (vault.isClaimed) revert VaultAlreadyClaimed();
        if (vault.amount == 0) revert NoDeposit();
        if (approvalValue != 1) revert InvalidApprovalValue();

        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(intentId, approvalValue));
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        
        address signer = recoverSigner(ethSignedMessageHash, signature);
        if (signer != verifier) revert UnauthorizedVerifier();

        uint256 amount = vault.amount;
        address token = vault.token;
        
        // Mark as claimed
        vault.isClaimed = true;
        vault.amount = 0;
        
        // Transfer tokens or ETH to solver (msg.sender)
        if (token == address(0)) {
            // ETH transfer
            payable(msg.sender).transfer(amount);
        } else {
            // ERC20 token transfer
            IERC20(token).safeTransfer(msg.sender, amount);
        }
        
        emit VaultClaimed(intentId, msg.sender, amount);
    }

    /**
     * @notice Cancel vault and return funds to maker (after expiry)
     * @param intentId Intent identifier
     */
    function cancel(uint256 intentId) external {
        Vault storage vault = vaults[intentId];
        
        if (vault.isClaimed) revert VaultAlreadyClaimed();
        if (vault.amount == 0) revert NoDeposit();
        if (msg.sender != vault.maker) revert UnauthorizedMaker();

        uint256 amount = vault.amount;
        address token = vault.token;
        
        // Reset vault
        vault.amount = 0;
        vault.isClaimed = true;
        
        // Transfer tokens or ETH back to maker
        if (token == address(0)) {
            // ETH transfer
            payable(vault.maker).transfer(amount);
        } else {
            // ERC20 token transfer
            IERC20(token).safeTransfer(vault.maker, amount);
        }
        
        emit VaultCancelled(intentId, vault.maker, amount);
    }

    /**
     * @notice Recover signer address from signature
     * @param messageHash Hash of the message
     * @param signature ECDSA signature
     * @return signer Address that signed the message
     */
    function recoverSigner(
        bytes32 messageHash,
        bytes memory signature
    ) internal pure returns (address) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        // Adjust v for Ethereum (27 or 28)
        if (v < 27) {
            v += 27;
        }

        require(v == 27 || v == 28, "Invalid signature v value");

        return ecrecover(messageHash, v, r, s);
    }

    /**
     * @notice Get vault data for an intent
     * @param intentId Intent identifier
     * @return maker Maker address
     * @return token Token address
     * @return amount Amount deposited
     * @return isClaimed Whether vault is claimed
     * @return expiry Expiry timestamp
     */
    function getVault(uint256 intentId)
        external
        view
        returns (
            address maker,
            address token,
            uint256 amount,
            bool isClaimed,
            uint256 expiry
        )
    {
        Vault memory vault = vaults[intentId];
        return (vault.maker, vault.token, vault.amount, vault.isClaimed, vault.expiry);
    }
}

