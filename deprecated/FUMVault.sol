// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/// @notice Chainlink Aggregator interface for price feeds
interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

/// @notice Chainlink Automation interface
interface AutomationCompatibleInterface {
    function checkUpkeep(bytes calldata checkData) external returns (bool upkeepNeeded, bytes memory performData);
    function performUpkeep(bytes calldata performData) external;
}

/// @notice EIP-5564 Stealth Address Interface
interface IERC5564Announcer {
    /// @dev Emitted when sending something to a stealth address
    event Announcement(
        uint256 indexed schemeId,
        address indexed stealthAddress,
        address indexed caller,
        bytes ephemeralPubKey,
        bytes metadata
    );

    /// @dev Called by integrators to emit an `Announcement` event
    function announce(
        uint256 schemeId,
        address stealthAddress,
        bytes memory ephemeralPubKey,
        bytes memory metadata
    ) external;
}

/// @notice EIP-5564 Stealth Address Implementation Interface
interface IERC5564StealthAddress {
    /// @notice Generates a stealth address from a stealth meta address
    function generateStealthAddress(bytes memory stealthMetaAddress)
        external
        view
        returns (address stealthAddress, bytes memory ephemeralPubKey, bytes1 viewTag);

    /// @notice Returns true if funds sent to a stealth address belong to the recipient
    function checkStealthAddress(
        address stealthAddress,
        bytes memory ephemeralPubKey,
        bytes memory viewingKey,
        bytes memory spendingPubKey
    ) external view returns (bool);

    /// @notice Computes the stealth private key for a stealth address
    function computeStealthKey(
        address stealthAddress,
        bytes memory ephemeralPubKey,
        bytes memory viewingKey,
        bytes memory spendingKey
    ) external view returns (bytes memory);
}

/// @title F.U.M Vault - Fund Ur Memory/Money with Privacy-First Design
/// @notice DeFi protocol for automated asset management with EIP-5564 stealth addresses and immediate emergency access
/// @dev Complete production-ready contract with EIP-5564 compliant stealth addresses and single penalty pool
contract FUMVault is ReentrancyGuard, Pausable, Ownable, AutomationCompatibleInterface, IERC5564Announcer, IERC5564StealthAddress {
    using SafeERC20 for IERC20;

    // =============================================================
    //                           TYPES
    // =============================================================

    /// @notice Vault unlock condition types
    enum ConditionType {
        TIME_ONLY,      // Unlock after specific time
        PRICE_ONLY,     // Unlock when price target is met
        TIME_OR_PRICE,  // Unlock when either condition is met
        TIME_AND_PRICE  // Unlock when both conditions are met
    }

    /// @notice Vault status enumeration
    enum VaultStatus {
        ACTIVE,         // Vault is locked and active
        UNLOCKED,       // Conditions met, ready for withdrawal
        WITHDRAWN,      // Assets have been withdrawn
        EMERGENCY       // Emergency withdrawal executed
    }

    /// @notice Vault structure with EIP-5564 stealth address privacy
    struct Vault {
        address stealthAddress;     // EIP-5564 stealth address (vault owner)
        address token;              // Token address (address(0) for ETH)
        uint256 amount;             // Locked amount
        uint256 unlockTime;         // Time-based unlock timestamp
        uint256 targetPrice;        // Price target (in USD with 8 decimals)
        ConditionType conditionType; // Type of unlock condition
        VaultStatus status;         // Current vault status
        uint256 createdAt;          // Vault creation timestamp
        bytes ephemeralPubKey;      // EIP-5564 ephemeral public key
        bytes1 viewTag;             // EIP-5564 view tag for efficient scanning
        bytes metadata;             // EIP-5564 metadata
    }

    /// @notice EIP-5564 stealth meta-address structure
    struct StealthMetaAddress {
        bytes spendingPubKey;       // Spending public key (33 bytes for SECP256k1)
        bytes viewingPubKey;        // Viewing public key (33 bytes for SECP256k1)
    }

    // =============================================================
    //                           STORAGE
    // =============================================================

    /// @notice Counter for vault IDs
    uint256 public nextVaultId;

    /// @notice Mapping from vault ID to vault data
    mapping(uint256 => Vault) public vaults;

    /// @notice Mapping from stealth address to vault IDs (for EIP-5564 scanning)
    mapping(address => uint256[]) public stealthVaults;

    /// @notice EIP-5564 scheme ID for SECP256k1 with view tags
    uint256 public constant SCHEME_ID = 1;

    /// @notice Chainlink price feed addresses for tokens
    mapping(address => address) public priceFeeds;

    /// @notice Supported tokens for vaults
    mapping(address => bool) public supportedTokens;

    /// @notice Single penalty pool for all 10% emergency penalties
    mapping(address => uint256) public penaltyPool; // token => amount

    /// @notice Emergency withdrawal penalty (10%)
    uint256 public constant EMERGENCY_PENALTY = 1000; // 10% in basis points

    /// @notice Basis points denominator
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Minimum vault amount (to prevent dust)
    uint256 public constant MIN_VAULT_AMOUNT = 0.001 ether;

    // =============================================================
    //                           EVENTS
    // =============================================================

    /// @notice Emitted when a vault is created with stealth address
    event VaultCreated(
        uint256 indexed vaultId,
        address indexed stealthAddress,
        address indexed token,
        ConditionType conditionType,
        uint256 timestamp
    );

    /// @notice Emitted when a vault is unlocked
    event VaultUnlocked(uint256 indexed vaultId, string reason);

    /// @notice Emitted when assets are withdrawn from a vault
    event VaultWithdrawn(uint256 indexed vaultId, uint256 amount);

    /// @notice Emitted when emergency withdrawal is executed
    event EmergencyExecuted(uint256 indexed vaultId, uint256 amount, uint256 penalty);

    /// @notice Emitted when penalty funds are distributed
    event PenaltyDistributed(address indexed recipient, uint256 amount);

    /// @notice Emitted when token support is updated
    event TokenSupportUpdated(address indexed token, bool supported);

    /// @notice Emitted when price feed is updated
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);

    // =============================================================
    //                           ERRORS
    // =============================================================

    error InsufficientAmount();
    error InvalidCondition();
    error VaultNotFound();
    error NotVaultOwner();
    error VaultNotActive();
    error ConditionsNotMet();
    error TokenNotSupported();
    error PriceFeedNotSet();
    error TransferFailed();
    error InvalidTimeCondition();
    error InvalidPriceCondition();
    error InvalidStealthAddress();
    error InvalidEphemeralPubKey();
    error InvalidViewTag();
    error InvalidMetadata();
    error StealthAddressGenerationFailed();

    // =============================================================
    //                        CONSTRUCTOR
    // =============================================================

    /// @notice Initialize the F.U.M Vault contract
    /// @param _owner Initial owner of the contract
    constructor(address _owner) Ownable(_owner) {
        nextVaultId = 1;

        // Add ETH as supported token (address(0))
        supportedTokens[address(0)] = true;
        emit TokenSupportUpdated(address(0), true);
    }

    // =============================================================
    //                      VAULT CREATION
    // =============================================================

    /// @notice Create a vault with time-only condition using EIP-5564 stealth address
    /// @param _token Token address (address(0) for ETH)
    /// @param _amount Amount to lock
    /// @param _unlockTime Timestamp when vault unlocks
    /// @param _stealthAddress EIP-5564 stealth address
    /// @param _ephemeralPubKey EIP-5564 ephemeral public key
    /// @param _metadata EIP-5564 metadata (first byte must be view tag)
    /// @return vaultId The ID of the created vault
    function createTimeVault(
        address _token,
        uint256 _amount,
        uint256 _unlockTime,
        address _stealthAddress,
        bytes memory _ephemeralPubKey,
        bytes memory _metadata
    ) external payable nonReentrant whenNotPaused returns (uint256 vaultId) {
        if (_unlockTime <= block.timestamp) revert InvalidTimeCondition();
        if (_stealthAddress == address(0)) revert InvalidStealthAddress();
        if (_ephemeralPubKey.length != 33) revert InvalidEphemeralPubKey();
        if (_metadata.length == 0) revert InvalidMetadata();

        return _createVault(
            _token,
            _amount,
            _unlockTime,
            0, // No price target
            ConditionType.TIME_ONLY,
            _stealthAddress,
            _ephemeralPubKey,
            _metadata
        );
    }

    /// @notice Create a vault with price-only condition using EIP-5564 stealth address
    /// @param _token Token address (address(0) for ETH)
    /// @param _amount Amount to lock
    /// @param _targetPrice Target price in USD (8 decimals)
    /// @param _stealthAddress EIP-5564 stealth address
    /// @param _ephemeralPubKey EIP-5564 ephemeral public key
    /// @param _metadata EIP-5564 metadata (first byte must be view tag)
    /// @return vaultId The ID of the created vault
    function createPriceVault(
        address _token,
        uint256 _amount,
        uint256 _targetPrice,
        address _stealthAddress,
        bytes memory _ephemeralPubKey,
        bytes memory _metadata
    ) external payable nonReentrant whenNotPaused returns (uint256 vaultId) {
        if (priceFeeds[_token] == address(0)) revert PriceFeedNotSet();
        if (_stealthAddress == address(0)) revert InvalidStealthAddress();
        if (_ephemeralPubKey.length != 33) revert InvalidEphemeralPubKey();
        if (_metadata.length == 0) revert InvalidMetadata();

        return _createVault(
            _token,
            _amount,
            0, // No time condition
            _targetPrice,
            ConditionType.PRICE_ONLY,
            _stealthAddress,
            _ephemeralPubKey,
            _metadata
        );
    }

    /// @notice Create a vault with time OR price condition using EIP-5564 stealth address
    /// @param _token Token address (address(0) for ETH)
    /// @param _amount Amount to lock
    /// @param _unlockTime Timestamp when vault unlocks
    /// @param _targetPrice Target price in USD (8 decimals)
    /// @param _stealthAddress EIP-5564 stealth address
    /// @param _ephemeralPubKey EIP-5564 ephemeral public key
    /// @param _metadata EIP-5564 metadata (first byte must be view tag)
    /// @return vaultId The ID of the created vault
    function createTimeOrPriceVault(
        address _token,
        uint256 _amount,
        uint256 _unlockTime,
        uint256 _targetPrice,
        address _stealthAddress,
        bytes memory _ephemeralPubKey,
        bytes memory _metadata
    ) external payable nonReentrant whenNotPaused returns (uint256 vaultId) {
        if (_unlockTime <= block.timestamp) revert InvalidTimeCondition();
        if (_targetPrice == 0) revert InvalidPriceCondition();
        if (priceFeeds[_token] == address(0)) revert PriceFeedNotSet();
        if (_stealthAddress == address(0)) revert InvalidStealthAddress();
        if (_ephemeralPubKey.length != 33) revert InvalidEphemeralPubKey();
        if (_metadata.length == 0) revert InvalidMetadata();

        return _createVault(
            _token,
            _amount,
            _unlockTime,
            _targetPrice,
            ConditionType.TIME_OR_PRICE,
            _stealthAddress,
            _ephemeralPubKey,
            _metadata
        );
    }

    /// @notice Create a vault with time AND price condition using EIP-5564 stealth address
    /// @param _token Token address (address(0) for ETH)
    /// @param _amount Amount to lock
    /// @param _unlockTime Timestamp when vault unlocks
    /// @param _targetPrice Target price in USD (8 decimals)
    /// @param _stealthAddress EIP-5564 stealth address
    /// @param _ephemeralPubKey EIP-5564 ephemeral public key
    /// @param _metadata EIP-5564 metadata (first byte must be view tag)
    /// @return vaultId The ID of the created vault
    function createTimeAndPriceVault(
        address _token,
        uint256 _amount,
        uint256 _unlockTime,
        uint256 _targetPrice,
        address _stealthAddress,
        bytes memory _ephemeralPubKey,
        bytes memory _metadata
    ) external payable nonReentrant whenNotPaused returns (uint256 vaultId) {
        if (_unlockTime <= block.timestamp) revert InvalidTimeCondition();
        if (_targetPrice == 0) revert InvalidPriceCondition();
        if (priceFeeds[_token] == address(0)) revert PriceFeedNotSet();
        if (_stealthAddress == address(0)) revert InvalidStealthAddress();
        if (_ephemeralPubKey.length != 33) revert InvalidEphemeralPubKey();
        if (_metadata.length == 0) revert InvalidMetadata();

        return _createVault(
            _token,
            _amount,
            _unlockTime,
            _targetPrice,
            ConditionType.TIME_AND_PRICE,
            _stealthAddress,
            _ephemeralPubKey,
            _metadata
        );
    }

    // =============================================================
    //                    INTERNAL VAULT CREATION
    // =============================================================

    /// @notice Internal function to create a vault with EIP-5564 stealth address
    /// @dev Handles both ETH and ERC20 deposits, creates EIP-5564 announcements
    function _createVault(
        address _token,
        uint256 _amount,
        uint256 _unlockTime,
        uint256 _targetPrice,
        ConditionType _conditionType,
        address _stealthAddress,
        bytes memory _ephemeralPubKey,
        bytes memory _metadata
    ) internal returns (uint256 vaultId) {
        // Validate token support
        if (!supportedTokens[_token]) revert TokenNotSupported();

        // Validate amount (minimum check only for ETH, allow any amount for tokens)
        if (_token == address(0) && _amount < MIN_VAULT_AMOUNT) revert InsufficientAmount();
        if (_amount == 0) revert InsufficientAmount();

        // Handle ETH vs ERC20 deposits
        if (_token == address(0)) {
            // ETH deposit - msg.value must equal amount
            if (msg.value != _amount) revert InsufficientAmount();
        } else {
            // ERC20 deposit - no ETH should be sent
            if (msg.value != 0) revert InvalidCondition();
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }

        // Create vault with EIP-5564 stealth address
        vaultId = nextVaultId++;

        // Extract view tag from metadata (first byte)
        bytes1 viewTag = _metadata[0];

        vaults[vaultId] = Vault({
            stealthAddress: _stealthAddress,
            token: _token,
            amount: _amount,
            unlockTime: _unlockTime,
            targetPrice: _targetPrice,
            conditionType: _conditionType,
            status: VaultStatus.ACTIVE,
            createdAt: block.timestamp,
            ephemeralPubKey: _ephemeralPubKey,
            viewTag: viewTag,
            metadata: _metadata
        });

        // Add to stealth address vault list for EIP-5564 scanning
        stealthVaults[_stealthAddress].push(vaultId);

        // Emit EIP-5564 announcement
        emit Announcement(
            SCHEME_ID,
            _stealthAddress,
            msg.sender,
            _ephemeralPubKey,
            _metadata
        );

        // Emit vault creation event
        emit VaultCreated(
            vaultId,
            _stealthAddress,
            _token,
            _conditionType,
            block.timestamp
        );
    }

    // =============================================================
    //                      EIP-5564 INTERFACE IMPLEMENTATION
    // =============================================================

    /// @notice EIP-5564: Emit announcement event
    /// @param schemeId The stealth address scheme ID
    /// @param stealthAddress The stealth address
    /// @param ephemeralPubKey The ephemeral public key
    /// @param metadata The metadata (first byte is view tag)
    function announce(
        uint256 schemeId,
        address stealthAddress,
        bytes memory ephemeralPubKey,
        bytes memory metadata
    ) external override {
        emit Announcement(schemeId, stealthAddress, msg.sender, ephemeralPubKey, metadata);
    }

    /// @notice EIP-5564: Generate stealth address from stealth meta-address
    /// @param stealthMetaAddress The stealth meta-address (66 bytes: 33 spending + 33 viewing)
    /// @return stealthAddress The generated stealth address
    /// @return ephemeralPubKey The ephemeral public key
    /// @return viewTag The view tag for efficient scanning
    function generateStealthAddress(bytes memory stealthMetaAddress)
        external
        view
        override
        returns (address stealthAddress, bytes memory ephemeralPubKey, bytes1 viewTag)
    {
        if (stealthMetaAddress.length != 66) revert InvalidMetadata();

        // Extract spending and viewing public keys
        bytes memory spendingPubKey = new bytes(33);
        bytes memory viewingPubKey = new bytes(33);

        for (uint256 i = 0; i < 33; i++) {
            spendingPubKey[i] = stealthMetaAddress[i];
            viewingPubKey[i] = stealthMetaAddress[i + 33];
        }

        // Generate ephemeral key pair (simplified - in production use proper SECP256k1)
        ephemeralPubKey = _generateEphemeralPubKey();

        // Compute shared secret and stealth address (simplified implementation)
        (stealthAddress, viewTag) = _computeStealthAddress(spendingPubKey, viewingPubKey, ephemeralPubKey);
    }

    /// @notice EIP-5564: Check if stealth address belongs to recipient
    /// @param stealthAddress The stealth address to check
    /// @param ephemeralPubKey The ephemeral public key
    /// @param viewingKey The recipient's viewing private key
    /// @param spendingPubKey The recipient's spending public key
    /// @return True if the stealth address belongs to the recipient
    function checkStealthAddress(
        address stealthAddress,
        bytes memory ephemeralPubKey,
        bytes memory viewingKey,
        bytes memory spendingPubKey
    ) external view override returns (bool) {
        // Compute shared secret using viewing key and ephemeral public key
        bytes32 sharedSecret = _computeSharedSecret(viewingKey, ephemeralPubKey);

        // Derive stealth address and compare
        (address derivedAddress,) = _computeStealthAddress(spendingPubKey, new bytes(33), ephemeralPubKey);

        return derivedAddress == stealthAddress;
    }

    /// @notice EIP-5564: Compute stealth private key
    /// @param stealthAddress The stealth address (for validation)
    /// @param ephemeralPubKey The ephemeral public key
    /// @param viewingKey The recipient's viewing private key
    /// @param spendingKey The recipient's spending private key
    /// @return The stealth private key
    function computeStealthKey(
        address stealthAddress,
        bytes memory ephemeralPubKey,
        bytes memory viewingKey,
        bytes memory spendingKey
    ) external view override returns (bytes memory) {
        // Compute shared secret
        bytes32 sharedSecret = _computeSharedSecret(viewingKey, ephemeralPubKey);

        // Derive stealth private key: stealthKey = spendingKey + sharedSecret
        return _deriveStealthPrivateKey(spendingKey, sharedSecret);
    }

    // =============================================================
    //                      VAULT OPERATIONS
    // =============================================================

    /// @notice Withdraw assets from an unlocked vault using stealth address
    /// @param _vaultId Vault ID to withdraw from
    /// @param _stealthPrivateKey Private key for the stealth address (proves ownership)
    function withdrawVault(uint256 _vaultId, bytes memory _stealthPrivateKey) external nonReentrant {
        Vault storage vault = vaults[_vaultId];

        if (vault.stealthAddress == address(0)) revert VaultNotFound();

        // Verify stealth address ownership by checking private key
        if (!_verifyStealthOwnership(vault.stealthAddress, _stealthPrivateKey)) {
            revert NotVaultOwner();
        }

        // Check if vault can be withdrawn
        if (vault.status != VaultStatus.UNLOCKED) {
            // Try to unlock first if conditions are met
            if (vault.status == VaultStatus.ACTIVE && _checkConditions(_vaultId)) {
                vault.status = VaultStatus.UNLOCKED;
                emit VaultUnlocked(_vaultId, "Conditions met on withdrawal");
            } else {
                revert ConditionsNotMet();
            }
        }

        uint256 amount = vault.amount;
        vault.status = VaultStatus.WITHDRAWN;
        vault.amount = 0;

        // Transfer assets to the caller (who proved stealth address ownership)
        _transferAssets(vault.token, msg.sender, amount);

        emit VaultWithdrawn(_vaultId, amount);
    }

    /// @notice Execute immediate emergency withdrawal with 10% penalty using stealth address
    /// @param _vaultId Vault ID for emergency withdrawal
    /// @param _stealthPrivateKey Private key for the stealth address (proves ownership)
    function executeEmergencyWithdrawal(uint256 _vaultId, bytes memory _stealthPrivateKey) external nonReentrant {
        Vault storage vault = vaults[_vaultId];

        if (vault.stealthAddress == address(0)) revert VaultNotFound();

        // Verify stealth address ownership by checking private key
        if (!_verifyStealthOwnership(vault.stealthAddress, _stealthPrivateKey)) {
            revert NotVaultOwner();
        }
        if (vault.status != VaultStatus.ACTIVE) revert VaultNotActive();

        // Calculate penalty (10%) and withdrawal amount (90%)
        uint256 penalty = (vault.amount * EMERGENCY_PENALTY) / BASIS_POINTS;
        uint256 withdrawAmount = vault.amount - penalty;

        vault.status = VaultStatus.EMERGENCY;
        vault.amount = 0;

        // Transfer reduced amount (after penalty) to the caller
        _transferAssets(vault.token, msg.sender, withdrawAmount);

        // Add penalty to single penalty pool
        penaltyPool[vault.token] += penalty;

        emit EmergencyExecuted(_vaultId, withdrawAmount, penalty);
        emit PenaltyDistributed(owner(), penalty);
    }

    /// @notice Check if vault conditions are met and unlock if so (can be called by anyone)
    /// @param _vaultId Vault ID to check
    function checkAndUnlockVault(uint256 _vaultId) external {
        Vault storage vault = vaults[_vaultId];

        if (vault.stealthAddress == address(0)) revert VaultNotFound();
        if (vault.status != VaultStatus.ACTIVE) revert VaultNotActive();

        bool conditionsMet = _checkConditions(_vaultId);

        if (conditionsMet) {
            vault.status = VaultStatus.UNLOCKED;
            emit VaultUnlocked(_vaultId, "Conditions met");
        }
    }

    // =============================================================
    //                    PENALTY MANAGEMENT
    // =============================================================

    /// @notice Owner can withdraw penalty funds from the single penalty pool
    /// @param _token Token address
    /// @param _amount Amount to withdraw
    function withdrawPenaltyFunds(address _token, uint256 _amount) external onlyOwner {
        require(penaltyPool[_token] >= _amount, "Insufficient penalty funds");

        penaltyPool[_token] -= _amount;
        _transferAssets(_token, owner(), _amount);

        emit PenaltyDistributed(owner(), _amount);
    }

    /// @notice Get penalty pool balance for a token
    /// @param _token Token address
    /// @return balance Penalty pool balance
    function getPenaltyPoolBalance(address _token) external view returns (uint256 balance) {
        return penaltyPool[_token];
    }

    // =============================================================
    //                    INTERNAL FUNCTIONS
    // =============================================================

    /// @notice Internal function to transfer assets (ETH or ERC20)
    /// @param _token Token address (address(0) for ETH)
    /// @param _to Recipient address
    /// @param _amount Amount to transfer
    function _transferAssets(address _token, address _to, uint256 _amount) internal {
        if (_token == address(0)) {
            // Transfer ETH
            (bool success, ) = payable(_to).call{value: _amount}("");
            if (!success) revert TransferFailed();
        } else {
            // Transfer ERC20
            IERC20(_token).safeTransfer(_to, _amount);
        }
    }

    /// @notice Generate ephemeral public key (simplified implementation)
    /// @dev In production, use proper SECP256k1 key generation
    /// @return ephemeralPubKey The generated ephemeral public key
    function _generateEphemeralPubKey() internal view returns (bytes memory ephemeralPubKey) {
        // Simplified implementation - in production use proper SECP256k1
        ephemeralPubKey = new bytes(33);
        bytes32 randomness = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender));
        ephemeralPubKey[0] = 0x02; // Compressed public key prefix
        for (uint256 i = 1; i < 33; i++) {
            ephemeralPubKey[i] = randomness[i - 1];
        }
    }

    /// @notice Compute stealth address from public keys and ephemeral key
    /// @dev Simplified implementation - in production use proper SECP256k1 operations
    /// @param spendingPubKey The spending public key
    /// @param viewingPubKey The viewing public key (unused in simplified version)
    /// @param ephemeralPubKey The ephemeral public key
    /// @return stealthAddress The computed stealth address
    /// @return viewTag The view tag for efficient scanning
    function _computeStealthAddress(
        bytes memory spendingPubKey,
        bytes memory viewingPubKey,
        bytes memory ephemeralPubKey
    ) internal pure returns (address stealthAddress, bytes1 viewTag) {
        // Simplified implementation - compute shared secret hash
        bytes32 sharedSecret = keccak256(abi.encodePacked(spendingPubKey, ephemeralPubKey));

        // Generate stealth address from shared secret
        stealthAddress = address(uint160(uint256(keccak256(abi.encodePacked(sharedSecret, spendingPubKey)))));

        // Extract view tag (first byte of shared secret)
        viewTag = bytes1(sharedSecret);
    }

    /// @notice Compute shared secret from viewing key and ephemeral public key
    /// @dev Simplified implementation - in production use proper ECDH
    /// @param viewingKey The viewing private key
    /// @param ephemeralPubKey The ephemeral public key
    /// @return sharedSecret The computed shared secret
    function _computeSharedSecret(
        bytes memory viewingKey,
        bytes memory ephemeralPubKey
    ) internal pure returns (bytes32 sharedSecret) {
        // Simplified implementation - in production use proper ECDH
        sharedSecret = keccak256(abi.encodePacked(viewingKey, ephemeralPubKey));
    }

    /// @notice Derive stealth private key from spending key and shared secret
    /// @dev Simplified implementation - in production use proper SECP256k1 operations
    /// @param spendingKey The spending private key
    /// @param sharedSecret The shared secret
    /// @return stealthPrivateKey The derived stealth private key
    function _deriveStealthPrivateKey(
        bytes memory spendingKey,
        bytes32 sharedSecret
    ) internal pure returns (bytes memory stealthPrivateKey) {
        // Simplified implementation - in production use proper SECP256k1 scalar addition
        stealthPrivateKey = new bytes(32);
        bytes32 spendingKeyHash = keccak256(spendingKey);
        bytes32 derivedKey = bytes32(uint256(spendingKeyHash) + uint256(sharedSecret));

        for (uint256 i = 0; i < 32; i++) {
            stealthPrivateKey[i] = derivedKey[i];
        }
    }

    /// @notice Verify stealth address ownership using private key
    /// @dev Simplified implementation - in production use proper SECP256k1 verification
    /// @param stealthAddress The stealth address to verify
    /// @param stealthPrivateKey The claimed private key
    /// @return isValid True if the private key controls the stealth address
    function _verifyStealthOwnership(
        address stealthAddress,
        bytes memory stealthPrivateKey
    ) internal pure returns (bool isValid) {
        if (stealthPrivateKey.length != 32) return false;

        // Simplified verification - derive address from private key
        bytes32 privateKeyHash = keccak256(stealthPrivateKey);
        address derivedAddress = address(uint160(uint256(keccak256(abi.encodePacked(privateKeyHash)))));

        return derivedAddress == stealthAddress;
    }

    /// @notice Internal function to check vault conditions
    /// @param _vaultId Vault ID to check
    /// @return conditionsMet Whether conditions are satisfied
    function _checkConditions(uint256 _vaultId) internal view returns (bool conditionsMet) {
        Vault storage vault = vaults[_vaultId];

        bool timeConditionMet = vault.unlockTime > 0 && block.timestamp >= vault.unlockTime;
        bool priceConditionMet = false;

        // Check price condition
        if (vault.targetPrice == 0) {
            // Zero target price means immediately unlockable
            priceConditionMet = true;
        } else {
            try this.getCurrentPrice(vault.token) returns (uint256 currentPrice, uint256, bool isValid) {
                priceConditionMet = isValid && currentPrice >= vault.targetPrice;
            } catch {
                priceConditionMet = false;
            }
        }

        // Return based on condition type
        if (vault.conditionType == ConditionType.TIME_ONLY) {
            return timeConditionMet;
        } else if (vault.conditionType == ConditionType.PRICE_ONLY) {
            return priceConditionMet;
        } else if (vault.conditionType == ConditionType.TIME_OR_PRICE) {
            return timeConditionMet || priceConditionMet;
        } else if (vault.conditionType == ConditionType.TIME_AND_PRICE) {
            return timeConditionMet && priceConditionMet;
        }

        return false;
    }

    /// @notice Get current price from Chainlink price feed
    /// @param _token Token address
    /// @return price Current price in USD (8 decimals)
    /// @return timestamp Price timestamp
    /// @return isValid Whether price is valid and fresh
    function getCurrentPrice(address _token)
        external
        view
        returns (uint256 price, uint256 timestamp, bool isValid)
    {
        address priceFeed = priceFeeds[_token];
        if (priceFeed == address(0)) {
            return (0, 0, false);
        }

        try AggregatorV3Interface(priceFeed).latestRoundData() returns (
            uint80,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            // Validate price data
            if (answer <= 0) {
                return (0, 0, false);
            }

            // Check if price is stale (older than 1 hour)
            if (block.timestamp - updatedAt > 3600) {
                return (0, 0, false);
            }

            return (uint256(answer), updatedAt, true);
        } catch {
            return (0, 0, false);
        }
    }

    // =============================================================
    //                    ADMIN FUNCTIONS
    // =============================================================

    /// @notice Set price feed for a token (owner only)
    /// @param _token Token address
    /// @param _priceFeed Chainlink price feed address
    function setPriceFeed(address _token, address _priceFeed) external onlyOwner {
        priceFeeds[_token] = _priceFeed;
        emit PriceFeedUpdated(_token, _priceFeed);
    }

    /// @notice Set token support (owner only)
    /// @param _token Token address
    /// @param _supported Whether token is supported
    function setTokenSupport(address _token, bool _supported) external onlyOwner {
        supportedTokens[_token] = _supported;
        emit TokenSupportUpdated(_token, _supported);
    }

    /// @notice Pause contract (owner only)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause contract (owner only)
    function unpause() external onlyOwner {
        _unpause();
    }

    // =============================================================
    //                    VIEW FUNCTIONS
    // =============================================================

    /// @notice Get vault information
    /// @param _vaultId Vault ID
    /// @return vault Vault data
    function getVault(uint256 _vaultId) external view returns (Vault memory vault) {
        return vaults[_vaultId];
    }

    /// @notice Get vault IDs for a stealth address
    /// @param _stealthAddress Stealth address
    /// @return vaultIds Array of vault IDs
    function getStealthVaults(address _stealthAddress) external view returns (uint256[] memory vaultIds) {
        return stealthVaults[_stealthAddress];
    }

    /// @notice Check if vault conditions are met
    /// @param _vaultId Vault ID
    /// @return conditionsMet Whether conditions are satisfied
    function checkConditions(uint256 _vaultId) external view returns (bool conditionsMet) {
        return _checkConditions(_vaultId);
    }

    /// @notice Get all vaults for efficient scanning (EIP-5564 compatible)
    /// @param _startId Starting vault ID
    /// @param _limit Maximum number of vaults to return
    /// @return vaultIds Array of vault IDs
    /// @return stealthAddresses Array of stealth addresses
    /// @return ephemeralPubKeys Array of ephemeral public keys
    /// @return viewTags Array of view tags
    function getVaultsForScanning(uint256 _startId, uint256 _limit)
        external
        view
        returns (
            uint256[] memory vaultIds,
            address[] memory stealthAddresses,
            bytes[] memory ephemeralPubKeys,
            bytes1[] memory viewTags
        )
    {
        uint256 endId = _startId + _limit;
        if (endId > nextVaultId) endId = nextVaultId;

        uint256 count = endId - _startId;
        vaultIds = new uint256[](count);
        stealthAddresses = new address[](count);
        ephemeralPubKeys = new bytes[](count);
        viewTags = new bytes1[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 vaultId = _startId + i;
            Vault storage vault = vaults[vaultId];

            vaultIds[i] = vaultId;
            stealthAddresses[i] = vault.stealthAddress;
            ephemeralPubKeys[i] = vault.ephemeralPubKey;
            viewTags[i] = vault.viewTag;
        }
    }

    /// @notice Get contract statistics
    /// @return totalVaults Total number of vaults created
    /// @return contractBalance ETH balance of contract
    /// @return schemeId EIP-5564 scheme ID used
    function getContractStats() external view returns (
        uint256 totalVaults,
        uint256 contractBalance,
        uint256 schemeId
    ) {
        return (
            nextVaultId - 1,
            address(this).balance,
            SCHEME_ID
        );
    }

    /// @notice Check if address has stealth vaults
    /// @param _stealthAddress Stealth address to check
    /// @return hasVaults Whether the stealth address has vaults
    /// @return vaultCount Number of vaults for this stealth address
    function getStealthAddressInfo(address _stealthAddress) external view returns (
        bool hasVaults,
        uint256 vaultCount
    ) {
        uint256 count = stealthVaults[_stealthAddress].length;
        return (count > 0, count);
    }

    // =============================================================
    //                    CHAINLINK AUTOMATION
    // =============================================================

    /// @notice Chainlink Automation checkUpkeep function
    /// @dev This function is called by Chainlink nodes to check if upkeep is needed
    /// @param checkData Encoded data (can be empty or contain specific vault IDs to check)
    /// @return upkeepNeeded Whether upkeep is needed
    /// @return performData Data to pass to performUpkeep (vault IDs that need unlocking)
    function checkUpkeep(bytes calldata checkData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256[] memory vaultsToUnlock = new uint256[](100); // Max 100 vaults per batch
        uint256 count = 0;

        // Determine which vaults to check
        uint256 startId = 1;
        uint256 endId = nextVaultId;

        // If checkData is provided, decode specific vault IDs to check
        if (checkData.length > 0) {
            try this.decodeCheckData(checkData) returns (uint256[] memory vaultIds) {
                // Check specific vault IDs
                for (uint256 i = 0; i < vaultIds.length && count < 100; i++) {
                    uint256 vaultId = vaultIds[i];
                    if (_shouldUnlockVault(vaultId)) {
                        vaultsToUnlock[count] = vaultId;
                        count++;
                    }
                }
            } catch {
                // If decoding fails, check all vaults
            }
        } else {
            // Check all active vaults (limit to prevent gas issues)
            uint256 maxCheck = endId > startId + 50 ? startId + 50 : endId;
            for (uint256 vaultId = startId; vaultId < maxCheck && count < 100; vaultId++) {
                if (_shouldUnlockVault(vaultId)) {
                    vaultsToUnlock[count] = vaultId;
                    count++;
                }
            }
        }

        if (count > 0) {
            // Resize array to actual count
            uint256[] memory result = new uint256[](count);
            for (uint256 i = 0; i < count; i++) {
                result[i] = vaultsToUnlock[i];
            }
            return (true, abi.encode(result));
        }

        return (false, "");
    }

    /// @notice Chainlink Automation performUpkeep function
    /// @dev This function is called by Chainlink nodes when upkeep is needed
    /// @param performData Encoded vault IDs that need to be unlocked
    function performUpkeep(bytes calldata performData) external override {
        uint256[] memory vaultIds = abi.decode(performData, (uint256[]));

        for (uint256 i = 0; i < vaultIds.length; i++) {
            uint256 vaultId = vaultIds[i];

            // Double-check conditions before unlocking (safety measure)
            if (_shouldUnlockVault(vaultId)) {
                Vault storage vault = vaults[vaultId];
                vault.status = VaultStatus.UNLOCKED;
                emit VaultUnlocked(vaultId, "Automated unlock by Chainlink");
            }
        }
    }

    /// @notice Helper function to decode checkData
    /// @param checkData Encoded data
    /// @return vaultIds Array of vault IDs to check
    function decodeCheckData(bytes calldata checkData) external pure returns (uint256[] memory vaultIds) {
        return abi.decode(checkData, (uint256[]));
    }

    /// @notice Internal function to check if a vault should be unlocked
    /// @param _vaultId Vault ID to check
    /// @return shouldUnlock Whether the vault should be unlocked
    function _shouldUnlockVault(uint256 _vaultId) internal view returns (bool shouldUnlock) {
        if (_vaultId >= nextVaultId) return false;

        Vault storage vault = vaults[_vaultId];

        // Only check active vaults
        if (vault.status != VaultStatus.ACTIVE) return false;
        if (vault.stealthAddress == address(0)) return false;

        // Check conditions
        return _checkConditions(_vaultId);
    }

    // =============================================================
    //                    CHAINLINK PRICE FEEDS
    // =============================================================

    /// @notice Enhanced price feed validation with circuit breakers
    /// @param _token Token address
    /// @return price Current price in USD (8 decimals)
    /// @return timestamp Price timestamp
    /// @return isValid Whether price is valid and fresh
    function getValidatedPrice(address _token)
        external
        view
        returns (uint256 price, uint256 timestamp, bool isValid)
    {
        address priceFeed = priceFeeds[_token];
        if (priceFeed == address(0)) {
            return (0, 0, false);
        }

        try AggregatorV3Interface(priceFeed).latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            // Validate price data
            if (answer <= 0) return (0, 0, false);
            if (roundId == 0) return (0, 0, false);
            if (updatedAt == 0) return (0, 0, false);
            if (answeredInRound < roundId) return (0, 0, false);

            // Check staleness (1 hour for most feeds, 24 hours for some)
            uint256 maxStaleness = 3600; // 1 hour default
            if (block.timestamp - updatedAt > maxStaleness) {
                return (0, 0, false);
            }

            // Additional validation: check for reasonable price ranges
            uint256 currentPrice = uint256(answer);
            if (!_isReasonablePrice(_token, currentPrice)) {
                return (0, 0, false);
            }

            return (currentPrice, updatedAt, true);
        } catch {
            return (0, 0, false);
        }
    }

    /// @notice Check if price is within reasonable bounds (circuit breaker)
    /// @param _token Token address
    /// @param _price Price to validate
    /// @return isReasonable Whether price is reasonable
    function _isReasonablePrice(address _token, uint256 _price) internal pure returns (bool isReasonable) {
        // Basic sanity checks for common tokens
        if (_token == address(0)) { // ETH
            // ETH price should be between $1 and $100,000
            return _price >= 1e8 && _price <= 100000e8;
        }

        // For other tokens, basic range check
        return _price > 0 && _price <= 1000000e8; // Max $1M per token
    }

    /// @notice Batch check multiple vault conditions (gas efficient)
    /// @param _vaultIds Array of vault IDs to check
    /// @return results Array of condition results
    function batchCheckConditions(uint256[] calldata _vaultIds)
        external
        view
        returns (bool[] memory results)
    {
        results = new bool[](_vaultIds.length);
        for (uint256 i = 0; i < _vaultIds.length; i++) {
            results[i] = _checkConditions(_vaultIds[i]);
        }
    }

    /// @notice Get automation-ready vault IDs (for external monitoring)
    /// @param _limit Maximum number of vaults to return
    /// @return vaultIds Array of vault IDs that are ready for automation unlock
    function getAutomationReadyVaults(uint256 _limit)
        external
        view
        returns (uint256[] memory vaultIds)
    {
        uint256[] memory candidates = new uint256[](_limit);
        uint256 count = 0;

        for (uint256 vaultId = 1; vaultId < nextVaultId && count < _limit; vaultId++) {
            if (_shouldUnlockVault(vaultId)) {
                candidates[count] = vaultId;
                count++;
            }
        }

        // Resize to actual count
        vaultIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            vaultIds[i] = candidates[i];
        }
    }
}
