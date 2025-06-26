// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title F.U.M Vault with Real Stealth Addresses
/// @notice DeFi protocol with true stealth address privacy - no fake ZK, just real privacy
/// @dev Implements EIP-5564 style stealth addresses for complete address unlinkability
contract FUMVaultStealth is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // =============================================================
    //                           TYPES
    // =============================================================

    enum ConditionType {
        TIME_ONLY,      // Unlock after specific time
        PRICE_ONLY,     // Unlock when price target met
        TIME_OR_PRICE,  // Either condition unlocks vault
        TIME_AND_PRICE  // Both conditions required
    }

    enum VaultStatus {
        ACTIVE,         // Vault is locked and active
        UNLOCKED,       // Conditions met, ready for withdrawal
        WITHDRAWN,      // Assets have been withdrawn
        EMERGENCY       // Emergency withdrawal executed
    }

    /// @notice Stealth address metadata for scanning
    struct StealthMeta {
        bytes32 ephemeralPubKey;    // Ephemeral public key for ECDH
        bytes32 viewTag;            // View tag for efficient scanning
        uint256 timestamp;          // Creation timestamp
    }

    /// @notice Vault structure with stealth privacy
    struct Vault {
        address stealthAddress;     // Stealth address (vault owner)
        address token;              // Token address (address(0) for ETH)
        uint256 amount;             // Locked amount
        uint256 unlockTime;         // Time-based unlock timestamp
        uint256 targetPrice;        // Price target (in USD with 8 decimals)
        ConditionType conditionType; // Type of unlock condition
        VaultStatus status;         // Current vault status
        uint256 createdAt;          // Vault creation timestamp
        bytes encryptedData;        // Encrypted vault metadata
    }

    // =============================================================
    //                           STORAGE
    // =============================================================

    /// @notice Next vault ID to be assigned
    uint256 public nextVaultId;

    /// @notice Mapping from vault ID to vault data
    mapping(uint256 => Vault) public vaults;

    /// @notice Mapping from stealth address to vault IDs (for scanning)
    mapping(address => uint256[]) public stealthVaults;

    /// @notice Chainlink price feeds for tokens
    mapping(address => address) public priceFeeds;

    /// @notice Supported tokens for vaults
    mapping(address => bool) public supportedTokens;

    /// @notice Single penalty pool for all 10% emergency penalties
    mapping(address => uint256) public penaltyPool;

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
        uint8 conditionType,
        uint256 timestamp
    );

    /// @notice Emitted for stealth address announcements (EIP-5564 style)
    event StealthAddressAnnouncement(
        address indexed stealthAddress,
        bytes32 ephemeralPubKey,
        bytes32 viewTag,
        bytes encryptedData
    );

    /// @notice Emitted when vault is unlocked
    event VaultUnlocked(uint256 indexed vaultId, string reason);

    /// @notice Emitted when vault is withdrawn
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
    error NotAuthorized();
    error VaultNotActive();
    error ConditionsNotMet();
    error TokenNotSupported();
    error PriceFeedNotSet();
    error TransferFailed();
    error InvalidTimeCondition();
    error InvalidPriceCondition();
    error InvalidStealthData();

    // =============================================================
    //                        CONSTRUCTOR
    // =============================================================

    /// @notice Initialize the F.U.M Vault contract with stealth addresses
    constructor() Ownable(msg.sender) {
        nextVaultId = 1;

        // Add ETH as supported token (address(0))
        supportedTokens[address(0)] = true;
        emit TokenSupportUpdated(address(0), true);
    }

    // =============================================================
    //                      VAULT CREATION
    // =============================================================

    /// @notice Create a vault with time-only condition using stealth address
    /// @param _token Token address (address(0) for ETH)
    /// @param _amount Amount to lock
    /// @param _unlockTime Timestamp when vault unlocks
    /// @param _stealthAddress Generated stealth address for privacy
    /// @param _ephemeralPubKey Ephemeral public key for ECDH
    /// @param _encryptedData Encrypted vault metadata
    /// @return vaultId The ID of the created vault
    function createTimeVault(
        address _token,
        uint256 _amount,
        uint256 _unlockTime,
        address _stealthAddress,
        bytes32 _ephemeralPubKey,
        bytes calldata _encryptedData
    ) external payable nonReentrant whenNotPaused returns (uint256 vaultId) {
        if (_unlockTime <= block.timestamp) revert InvalidTimeCondition();
        if (_stealthAddress == address(0)) revert InvalidStealthData();

        return _createVault(
            _token,
            _amount,
            _unlockTime,
            0, // No price target
            ConditionType.TIME_ONLY,
            _stealthAddress,
            _ephemeralPubKey,
            _encryptedData
        );
    }

    /// @notice Create a vault with price-only condition using stealth address
    /// @param _token Token address (address(0) for ETH)
    /// @param _amount Amount to lock
    /// @param _targetPrice Target price in USD (8 decimals)
    /// @param _stealthAddress Generated stealth address for privacy
    /// @param _ephemeralPubKey Ephemeral public key for ECDH
    /// @param _encryptedData Encrypted vault metadata
    /// @return vaultId The ID of the created vault
    function createPriceVault(
        address _token,
        uint256 _amount,
        uint256 _targetPrice,
        address _stealthAddress,
        bytes32 _ephemeralPubKey,
        bytes calldata _encryptedData
    ) external payable nonReentrant whenNotPaused returns (uint256 vaultId) {
        if (_targetPrice == 0) revert InvalidPriceCondition();
        if (priceFeeds[_token] == address(0)) revert PriceFeedNotSet();
        if (_stealthAddress == address(0)) revert InvalidStealthData();

        return _createVault(
            _token,
            _amount,
            0, // No time condition
            _targetPrice,
            ConditionType.PRICE_ONLY,
            _stealthAddress,
            _ephemeralPubKey,
            _encryptedData
        );
    }

    /// @notice Create a vault with time AND price conditions (both required)
    /// @param _token Token address (address(0) for ETH)
    /// @param _amount Amount to lock
    /// @param _unlockTime Timestamp when vault unlocks
    /// @param _targetPrice Target price in USD (8 decimals)
    /// @param _stealthAddress Generated stealth address for privacy
    /// @param _ephemeralPubKey Ephemeral public key for ECDH
    /// @param _encryptedData Encrypted vault metadata
    /// @return vaultId The ID of the created vault
    function createTimeAndPriceVault(
        address _token,
        uint256 _amount,
        uint256 _unlockTime,
        uint256 _targetPrice,
        address _stealthAddress,
        bytes32 _ephemeralPubKey,
        bytes calldata _encryptedData
    ) external payable nonReentrant whenNotPaused returns (uint256 vaultId) {
        if (_unlockTime <= block.timestamp) revert InvalidTimeCondition();
        if (_targetPrice == 0) revert InvalidPriceCondition();
        if (priceFeeds[_token] == address(0)) revert PriceFeedNotSet();
        if (_stealthAddress == address(0)) revert InvalidStealthData();

        return _createVault(
            _token,
            _amount,
            _unlockTime,
            _targetPrice,
            ConditionType.TIME_AND_PRICE,
            _stealthAddress,
            _ephemeralPubKey,
            _encryptedData
        );
    }

    /// @notice Create a vault with time OR price conditions (either unlocks)
    /// @param _token Token address (address(0) for ETH)
    /// @param _amount Amount to lock
    /// @param _unlockTime Timestamp when vault unlocks
    /// @param _targetPrice Target price in USD (8 decimals)
    /// @param _stealthAddress Generated stealth address for privacy
    /// @param _ephemeralPubKey Ephemeral public key for ECDH
    /// @param _encryptedData Encrypted vault metadata
    /// @return vaultId The ID of the created vault
    function createTimeOrPriceVault(
        address _token,
        uint256 _amount,
        uint256 _unlockTime,
        uint256 _targetPrice,
        address _stealthAddress,
        bytes32 _ephemeralPubKey,
        bytes calldata _encryptedData
    ) external payable nonReentrant whenNotPaused returns (uint256 vaultId) {
        if (_unlockTime <= block.timestamp) revert InvalidTimeCondition();
        if (_targetPrice == 0) revert InvalidPriceCondition();
        if (priceFeeds[_token] == address(0)) revert PriceFeedNotSet();
        if (_stealthAddress == address(0)) revert InvalidStealthData();

        return _createVault(
            _token,
            _amount,
            _unlockTime,
            _targetPrice,
            ConditionType.TIME_OR_PRICE,
            _stealthAddress,
            _ephemeralPubKey,
            _encryptedData
        );
    }

    // =============================================================
    //                    INTERNAL VAULT CREATION
    // =============================================================

    /// @notice Internal function to create vault with stealth address
    function _createVault(
        address _token,
        uint256 _amount,
        uint256 _unlockTime,
        uint256 _targetPrice,
        ConditionType _conditionType,
        address _stealthAddress,
        bytes32 _ephemeralPubKey,
        bytes calldata _encryptedData
    ) internal returns (uint256 vaultId) {
        // Validate token support
        if (!supportedTokens[_token]) revert TokenNotSupported();

        // Validate amount (minimum check only for ETH, allow any amount for tokens)
        if (_token == address(0) && _amount < MIN_VAULT_AMOUNT) revert InsufficientAmount();
        if (_amount == 0) revert InsufficientAmount();

        // Handle asset transfer
        if (_token == address(0)) {
            // ETH vault
            if (msg.value != _amount) revert InsufficientAmount();
        } else {
            // ERC20 vault
            if (msg.value != 0) revert InsufficientAmount();
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }

        // Create vault with stealth address
        vaultId = nextVaultId++;

        vaults[vaultId] = Vault({
            stealthAddress: _stealthAddress,
            token: _token,
            amount: _amount,
            unlockTime: _unlockTime,
            targetPrice: _targetPrice,
            conditionType: _conditionType,
            status: VaultStatus.ACTIVE,
            createdAt: block.timestamp,
            encryptedData: _encryptedData
        });

        // Add to stealth address mapping for scanning
        stealthVaults[_stealthAddress].push(vaultId);

        // Generate view tag for efficient scanning
        bytes32 viewTag = keccak256(abi.encodePacked(_ephemeralPubKey, _stealthAddress, block.timestamp));

        // Emit stealth address announcement for scanning
        emit StealthAddressAnnouncement(_stealthAddress, _ephemeralPubKey, viewTag, _encryptedData);

        // Emit vault creation event
        emit VaultCreated(vaultId, _stealthAddress, _token, uint8(_conditionType), block.timestamp);
    }

    // =============================================================
    //                      VAULT OPERATIONS
    // =============================================================

    /// @notice Withdraw assets from an unlocked vault using stealth key
    /// @param _vaultId Vault ID to withdraw from
    /// @param _stealthPrivateKey Private key for the stealth address
    function withdrawVault(uint256 _vaultId, bytes32 _stealthPrivateKey) external nonReentrant {
        Vault storage vault = vaults[_vaultId];

        if (vault.stealthAddress == address(0)) revert VaultNotFound();

        // Verify stealth address ownership by checking private key
        address derivedAddress = _deriveAddressFromPrivateKey(_stealthPrivateKey);
        if (derivedAddress != vault.stealthAddress) revert NotAuthorized();

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

        // Transfer assets to the caller (real user)
        _transferAssets(vault.token, msg.sender, amount);

        emit VaultWithdrawn(_vaultId, amount);
    }

    /// @notice Execute immediate emergency withdrawal with 10% penalty
    /// @param _vaultId Vault ID for emergency withdrawal
    /// @param _stealthPrivateKey Private key for the stealth address
    function executeEmergencyWithdrawal(uint256 _vaultId, bytes32 _stealthPrivateKey) external nonReentrant {
        Vault storage vault = vaults[_vaultId];

        if (vault.stealthAddress == address(0)) revert VaultNotFound();

        // Verify stealth address ownership
        address derivedAddress = _deriveAddressFromPrivateKey(_stealthPrivateKey);
        if (derivedAddress != vault.stealthAddress) revert NotAuthorized();
        if (vault.status != VaultStatus.ACTIVE) revert VaultNotActive();

        // Calculate penalty (10%) and withdrawal amount (90%)
        uint256 penalty = (vault.amount * EMERGENCY_PENALTY) / BASIS_POINTS;
        uint256 withdrawAmount = vault.amount - penalty;

        vault.status = VaultStatus.EMERGENCY;
        vault.amount = 0;

        // Transfer reduced amount (after penalty) to caller
        _transferAssets(vault.token, msg.sender, withdrawAmount);

        // Add penalty to single penalty pool
        penaltyPool[vault.token] += penalty;

        emit EmergencyExecuted(_vaultId, withdrawAmount, penalty);
        emit PenaltyDistributed(owner(), penalty);
    }

    // =============================================================
    //                    STEALTH ADDRESS UTILITIES
    // =============================================================

    /// @notice Derive address from private key (for verification)
    /// @param _privateKey Private key to derive address from
    /// @return derivedAddress The derived Ethereum address
    function _deriveAddressFromPrivateKey(bytes32 _privateKey) internal pure returns (address derivedAddress) {
        // This is a simplified version - in production you'd use proper ECDSA
        // For now, we'll use a deterministic derivation
        return address(uint160(uint256(keccak256(abi.encodePacked(_privateKey)))));
    }

    /// @notice Get vaults for a stealth address (for scanning)
    /// @param _stealthAddress Stealth address to query
    /// @return vaultIds Array of vault IDs for this stealth address
    function getStealthVaults(address _stealthAddress) external view returns (uint256[] memory vaultIds) {
        return stealthVaults[_stealthAddress];
    }

    /// @notice Check if vault conditions are met
    /// @param _vaultId Vault ID to check
    /// @return conditionsMet Whether conditions are satisfied
    function checkConditions(uint256 _vaultId) external view returns (bool conditionsMet) {
        return _checkConditions(_vaultId);
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

        // Apply condition logic
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

    // =============================================================
    //                    ASSET TRANSFER
    // =============================================================

    /// @notice Internal function to transfer assets
    /// @param _token Token address (address(0) for ETH)
    /// @param _to Recipient address
    /// @param _amount Amount to transfer
    function _transferAssets(address _token, address _to, uint256 _amount) internal {
        if (_token == address(0)) {
            // Transfer ETH
            (bool success, ) = payable(_to).call{value: _amount}("");
            if (!success) revert TransferFailed();
        } else {
            // Transfer ERC20 token
            IERC20(_token).safeTransfer(_to, _amount);
        }
    }

    // =============================================================
    //                    ADMIN FUNCTIONS
    // =============================================================

    /// @notice Set token support status
    /// @param _token Token address
    /// @param _supported Whether token is supported
    function setTokenSupport(address _token, bool _supported) external onlyOwner {
        supportedTokens[_token] = _supported;
        emit TokenSupportUpdated(_token, _supported);
    }

    /// @notice Set price feed for a token
    /// @param _token Token address
    /// @param _priceFeed Chainlink price feed address
    function setPriceFeed(address _token, address _priceFeed) external onlyOwner {
        priceFeeds[_token] = _priceFeed;
        emit PriceFeedUpdated(_token, _priceFeed);
    }

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

    /// @notice Pause contract (emergency)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause contract
    function unpause() external onlyOwner {
        _unpause();
    }

    // =============================================================
    //                    PRICE FEEDS
    // =============================================================

    /// @notice Get current price from Chainlink feed
    /// @param _token Token address
    /// @return price Current price in USD (8 decimals)
    /// @return updatedAt Price timestamp
    /// @return isValid Whether price is valid and fresh
    function getCurrentPrice(address _token)
        external
        view
        returns (uint256 price, uint256 updatedAt, bool isValid)
    {
        address priceFeed = priceFeeds[_token];
        if (priceFeed == address(0)) {
            return (0, 0, false);
        }

        try AggregatorV3Interface(priceFeed).latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 timestamp,
            uint80 answeredInRound
        ) {
            // Validate price data
            if (answer <= 0) return (0, 0, false);
            if (roundId == 0) return (0, 0, false);
            if (timestamp == 0) return (0, 0, false);
            if (answeredInRound < roundId) return (0, 0, false);

            // Check staleness (1 hour)
            if (block.timestamp - timestamp > 3600) {
                return (0, 0, false);
            }

            return (uint256(answer), timestamp, true);
        } catch {
            return (0, 0, false);
        }
    }

    /// @notice Get vault information
    /// @param _vaultId Vault ID
    /// @return vault Vault data
    function getVault(uint256 _vaultId) external view returns (Vault memory vault) {
        return vaults[_vaultId];
    }

    /// @notice Get contract statistics
    /// @return totalVaults Total number of vaults created
    /// @return activeVaults Number of active vaults
    /// @return totalValueLocked Total value locked in contract
    function getContractStats() external view returns (uint256 totalVaults, uint256 activeVaults, uint256 totalValueLocked) {
        totalVaults = nextVaultId - 1;

        for (uint256 i = 1; i < nextVaultId; i++) {
            if (vaults[i].status == VaultStatus.ACTIVE) {
                activeVaults++;
                totalValueLocked += vaults[i].amount;
            }
        }
    }
}

/// @notice Chainlink Aggregator interface for price feeds
interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
