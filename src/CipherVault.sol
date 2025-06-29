// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/v0.8/interfaces/AutomationCompatibleInterface.sol";

/// @title CipherVault - Commitment Protocol Vault
/// @notice A DeFi protocol for automated asset management using encoded commitment contracts
contract CipherVault is ReentrancyGuard, Pausable, Ownable, AutomationCompatibleInterface {
    using SafeERC20 for IERC20;
    using Address for address payable;

    // =============================================================
    //                           TYPES
    // =============================================================

    /// @notice Condition types for vault unlocking
    enum ConditionType {
        TIME_ONLY,
        PRICE_ONLY,
        TIME_OR_PRICE,
        TIME_AND_PRICE
    }

    /// @notice Vault status enumeration
    enum VaultStatus {
        ACTIVE,
        UNLOCKED,
        WITHDRAWN,
        EMERGENCY
    }

    /// @notice Vault structure containing all vault data
    struct Vault {
        address owner;
        address token;
        uint256 amount;
        uint256 unlockTime;
        uint256 targetPrice;
        ConditionType conditionType;
        VaultStatus status;
        uint256 createdAt;
        uint256 emergencyInitiated;
    }

    /// @notice Emergency withdrawal penalty structure
    struct EmergencyPenalty {
        uint256 amount;
        uint256 penaltyTime;
        bool claimed;
    }

    // =============================================================
    //                           STORAGE
    // =============================================================

    /// @notice Counter for vault IDs
    uint256 public nextVaultId;

    /// @notice Mapping from vault ID to vault data
    mapping(uint256 => Vault) public vaults;

    /// @notice Mapping from user to their emergency penalty data
    mapping(address => EmergencyPenalty) public emergencyPenalties;

    /// @notice Mapping from owner to their vault IDs
    mapping(address => uint256[]) public ownerVaults;

    /// @notice Chainlink price feed addresses for tokens
    mapping(address => address) public priceFeeds;

    /// @notice Price feed heartbeat (max time between updates) for each token
    mapping(address => uint256) public priceFeedHeartbeats;

    /// @notice Supported tokens for vaults
    mapping(address => bool) public supportedTokens;

    /// @notice Emergency withdrawal penalty (10%)
    uint256 public constant EMERGENCY_PENALTY = 1000; // 10% in basis points

    /// @notice Penalty claim delay (3 months)
    uint256 public constant PENALTY_CLAIM_DELAY = 90 days;

    /// @notice Basis points denominator
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Minimum vault amount (to prevent dust)
    uint256 public constant MIN_VAULT_AMOUNT = 0.001 ether; // not used

    /// @notice Maximum price staleness (1 hour default)
    uint256 public constant MAX_PRICE_STALENESS = 3600;

    /// @notice Price feed decimals for normalization
    mapping(address => uint8) public priceFeedDecimals;

    // =============================================================
    //                           EVENTS
    // =============================================================

    /// @notice Emitted when a new vault is created
    event VaultCreated(
        uint256 indexed vaultId,
        address indexed owner,
        address token,
        uint256 amount,
        uint256 unlockTime,
        uint256 targetPrice,
        ConditionType conditionType
    );

    /// @notice Emitted when a vault is unlocked
    event VaultUnlocked(uint256 indexed vaultId, address indexed owner);

    /// @notice Emitted when funds are withdrawn from a vault
    event VaultWithdrawn(uint256 indexed vaultId, address indexed owner, uint256 amount);

    /// @notice Emitted when emergency withdrawal is initiated
    event EmergencyWithdrawalInitiated(uint256 indexed vaultId, address indexed owner, uint256 penaltyAmount);

    /// @notice Emitted when penalty is claimed
    event PenaltyClaimed(address indexed user, uint256 amount);

    /// @notice Emitted when a price feed is updated
    event PriceFeedUpdated(address indexed token, address indexed priceFeed, uint256 heartbeat);

    /// @notice Emitted when token support is updated
    event TokenSupportUpdated(address indexed token, bool supported);

    // =============================================================
    //                           ERRORS
    // =============================================================

    error InvalidToken();
    error InvalidAmount();
    error InvalidTime();
    error InvalidPrice();
    error VaultNotFound();
    error VaultNotActive();
    error VaultNotUnlocked();
    error VaultAlreadyWithdrawn();
    error NotVaultOwner();
    error EmergencyNotInitiated();
    error PenaltyClaimTooEarly();
    error NoPenaltyToClaim();
    error PriceFeedNotSet();
    error PriceFeedStale();
    error TransferFailed();
    error InsufficientBalance();

    // =============================================================
    //                        CONSTRUCTOR
    // =============================================================

    constructor() Ownable(msg.sender) {
        nextVaultId = 1;
    }

    // =============================================================
    //                      VAULT CREATION
    // =============================================================

    /// @notice Create a time-based vault
    /// @param token Token address (address(0) for native token)
    /// @param amount Amount to lock
    /// @param unlockTime Timestamp when vault unlocks
    /// @return vaultId The ID of the created vault
    function createTimeVault(
        address token,
        uint256 amount,
        uint256 unlockTime
    ) external payable returns (uint256 vaultId) {
        return _createVault(token, amount, unlockTime, 0, ConditionType.TIME_ONLY);
    }

    /// @notice Create a price-based vault
    /// @param token Token address (address(0) for native token)
    /// @param amount Amount to lock
    /// @param targetPrice Target price for unlocking (in price feed decimals)
    /// @return vaultId The ID of the created vault
    function createPriceVault(
        address token,
        uint256 amount,
        uint256 targetPrice
    ) external payable returns (uint256 vaultId) {
        return _createVault(token, amount, 0, targetPrice, ConditionType.PRICE_ONLY);
    }

    /// @notice Create a time OR price vault (unlocks when either condition is met)
    /// @param token Token address (address(0) for native token)
    /// @param amount Amount to lock
    /// @param unlockTime Timestamp when vault unlocks
    /// @param targetPrice Target price for unlocking (in price feed decimals)
    /// @return vaultId The ID of the created vault
    function createTimeOrPriceVault(
        address token,
        uint256 amount,
        uint256 unlockTime,
        uint256 targetPrice
    ) external payable returns (uint256 vaultId) {
        return _createVault(token, amount, unlockTime, targetPrice, ConditionType.TIME_OR_PRICE);
    }

    /// @notice Create a time AND price vault (unlocks when both conditions are met)
    /// @param token Token address (address(0) for native token)
    /// @param amount Amount to lock
    /// @param unlockTime Timestamp when vault unlocks
    /// @param targetPrice Target price for unlocking (in price feed decimals)
    /// @return vaultId The ID of the created vault
    function createTimeAndPriceVault(
        address token,
        uint256 amount,
        uint256 unlockTime,
        uint256 targetPrice
    ) external payable returns (uint256 vaultId) {
        return _createVault(token, amount, unlockTime, targetPrice, ConditionType.TIME_AND_PRICE);
    }

    /// @notice Internal function to create vaults
    function _createVault(
        address token,
        uint256 amount,
        uint256 unlockTime,
        uint256 targetPrice,
        ConditionType conditionType
    ) internal nonReentrant whenNotPaused returns (uint256 vaultId) {
        // Validation
        if (token != address(0) && !supportedTokens[token]) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();
        
        // Condition-specific validation
        if (conditionType == ConditionType.TIME_ONLY || conditionType == ConditionType.TIME_OR_PRICE || conditionType == ConditionType.TIME_AND_PRICE) {
            if (unlockTime <= block.timestamp) revert InvalidTime();
        }
        
        if (conditionType == ConditionType.PRICE_ONLY || conditionType == ConditionType.TIME_OR_PRICE || conditionType == ConditionType.TIME_AND_PRICE) {
            if (targetPrice == 0) revert InvalidPrice();
            if (priceFeeds[token] == address(0)) revert PriceFeedNotSet();
        }

        // Handle payment
        if (token == address(0)) {
            // Native token
            if (msg.value != amount) revert InvalidAmount();
        } else {
            // ERC20 token
            if (msg.value != 0) revert InvalidAmount();
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Create vault
        vaultId = nextVaultId++;
        vaults[vaultId] = Vault({
            owner: msg.sender,
            token: token,
            amount: amount,
            unlockTime: unlockTime,
            targetPrice: targetPrice,
            conditionType: conditionType,
            status: VaultStatus.ACTIVE,
            createdAt: block.timestamp,
            emergencyInitiated: 0
        });

        ownerVaults[msg.sender].push(vaultId);

        emit VaultCreated(vaultId, msg.sender, token, amount, unlockTime, targetPrice, conditionType);
    }

    // =============================================================
    //                      VAULT OPERATIONS
    // =============================================================

    /// @notice Check if a vault can be unlocked
    /// @param vaultId The vault ID to check
    /// @return canUnlock Whether the vault can be unlocked
    function canUnlockVault(uint256 vaultId) public view returns (bool canUnlock) {
        Vault storage vault = vaults[vaultId];
        
        if (vault.owner == address(0) || vault.status != VaultStatus.ACTIVE) {
            return false;
        }

        if (vault.conditionType == ConditionType.TIME_ONLY) {
            return block.timestamp >= vault.unlockTime;
        } else if (vault.conditionType == ConditionType.PRICE_ONLY) {
            return _isPriceConditionMet(vault.token, vault.targetPrice);
        } else if (vault.conditionType == ConditionType.TIME_OR_PRICE) {
            return block.timestamp >= vault.unlockTime || _isPriceConditionMet(vault.token, vault.targetPrice);
        } else if (vault.conditionType == ConditionType.TIME_AND_PRICE) {
            return block.timestamp >= vault.unlockTime && _isPriceConditionMet(vault.token, vault.targetPrice);
        }

        return false;
    }

    /// @notice Unlock a vault when conditions are met
    /// @param vaultId The vault ID to unlock
    function unlockVault(uint256 vaultId) external nonReentrant {
        Vault storage vault = vaults[vaultId];
        
        if (vault.owner == address(0)) revert VaultNotFound();
        if (vault.status != VaultStatus.ACTIVE) revert VaultNotActive();
        if (!canUnlockVault(vaultId)) revert VaultNotUnlocked();

        vault.status = VaultStatus.UNLOCKED;
        emit VaultUnlocked(vaultId, vault.owner);
    }

    /// @notice Withdraw funds from an unlocked vault
    /// @param vaultId The vault ID to withdraw from
    function withdrawVault(uint256 vaultId) external nonReentrant {
        Vault storage vault = vaults[vaultId];
        
        if (vault.owner != msg.sender) revert NotVaultOwner();
        if (vault.status != VaultStatus.UNLOCKED) revert VaultNotUnlocked();

        vault.status = VaultStatus.WITHDRAWN;
        
        // Transfer funds
        if (vault.token == address(0)) {
            payable(msg.sender).sendValue(vault.amount);
        } else {
            IERC20(vault.token).safeTransfer(msg.sender, vault.amount);
        }

        emit VaultWithdrawn(vaultId, msg.sender, vault.amount);
    }

    /// @notice Emergency withdrawal with penalty
    /// @param vaultId The vault ID for emergency withdrawal
    function emergencyWithdraw(uint256 vaultId) external nonReentrant {
        Vault storage vault = vaults[vaultId];
        
        if (vault.owner != msg.sender) revert NotVaultOwner();
        if (vault.status != VaultStatus.ACTIVE) revert VaultNotActive();

        vault.status = VaultStatus.EMERGENCY;
        vault.emergencyInitiated = block.timestamp;

        uint256 penaltyAmount = (vault.amount * EMERGENCY_PENALTY) / BASIS_POINTS;
        uint256 withdrawAmount = vault.amount - penaltyAmount;

        // Store penalty for later claim
        emergencyPenalties[msg.sender].amount += penaltyAmount;
        emergencyPenalties[msg.sender].penaltyTime = block.timestamp;

        // Transfer funds minus penalty
        if (vault.token == address(0)) {
            payable(msg.sender).sendValue(withdrawAmount);
        } else {
            IERC20(vault.token).safeTransfer(msg.sender, withdrawAmount);
        }

        emit EmergencyWithdrawalInitiated(vaultId, msg.sender, penaltyAmount);
    }

    /// @notice Claim penalty after delay period
    function claimPenalty() external nonReentrant {
        EmergencyPenalty storage penalty = emergencyPenalties[msg.sender];
        
        if (penalty.amount == 0) revert NoPenaltyToClaim();
        if (penalty.claimed) revert NoPenaltyToClaim();
        if (block.timestamp < penalty.penaltyTime + PENALTY_CLAIM_DELAY) revert PenaltyClaimTooEarly();

        uint256 amount = penalty.amount;
        penalty.claimed = true;

        payable(msg.sender).sendValue(amount);
        emit PenaltyClaimed(msg.sender, amount);
    }

    // =============================================================
    //                      PRICE LOGIC
    // =============================================================

    /// @notice Check if price condition is met
    /// @param token Token to check price for
    /// @param targetPrice Target price to compare against
    /// @return met Whether the price condition is met
    function _isPriceConditionMet(address token, uint256 targetPrice) internal view returns (bool met) {
        if (priceFeeds[token] == address(0)) return false;

        try AggregatorV3Interface(priceFeeds[token]).latestRoundData() returns (
            uint80,
            int256 price,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            // Check staleness
            if (block.timestamp - updatedAt > priceFeedHeartbeats[token]) return false;
            if (price <= 0) return false;

            // Compare prices (assuming target price is in same decimals as price feed)
            return uint256(price) >= targetPrice;
        } catch {
            return false;
        }
    }

    /// @notice Get current price for a token
    /// @param token Token to get price for
    /// @return price Current price (0 if unavailable)
    /// @return decimals Price decimals
    function getCurrentPrice(address token) external view returns (uint256 price, uint8 decimals) {
        if (priceFeeds[token] == address(0)) return (0, 0);

        try AggregatorV3Interface(priceFeeds[token]).latestRoundData() returns (
            uint80,
            int256 latestPrice,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            // Check staleness
            if (block.timestamp - updatedAt > priceFeedHeartbeats[token]) return (0, 0);
            if (latestPrice <= 0) return (0, 0);

            return (uint256(latestPrice), priceFeedDecimals[token]);
        } catch {
            return (0, 0);
        }
    }

    // =============================================================
    //                   CHAINLINK AUTOMATION
    // =============================================================

    /// @notice Check if upkeep is needed (Chainlink Automation)
    /// @param checkData Additional data for upkeep check
    /// @return upkeepNeeded Whether upkeep is needed
    /// @return performData Data to pass to performUpkeep
    function checkUpkeep(bytes calldata checkData) external view override returns (bool upkeepNeeded, bytes memory performData) {
        // Check first 10 active vaults that might need unlocking
        uint256[] memory unlockedVaults = new uint256[](10);
        uint256 count = 0;
        
        for (uint256 i = 1; i < nextVaultId && count < 10; i++) {
            if (vaults[i].status == VaultStatus.ACTIVE && canUnlockVault(i)) {
                unlockedVaults[count] = i;
                count++;
            }
        }
        
        if (count > 0) {
            // Resize array to actual count
            uint256[] memory result = new uint256[](count);
            for (uint256 i = 0; i < count; i++) {
                result[i] = unlockedVaults[i];
            }
            return (true, abi.encode(result));
        }
        
        return (false, "");
    }

    /// @notice Perform upkeep (Chainlink Automation)
    /// @param performData Data from checkUpkeep
    function performUpkeep(bytes calldata performData) external override {
        uint256[] memory vaultIds = abi.decode(performData, (uint256[]));
        
        for (uint256 i = 0; i < vaultIds.length; i++) {
            uint256 vaultId = vaultIds[i];
            if (vaults[vaultId].status == VaultStatus.ACTIVE && canUnlockVault(vaultId)) {
                vaults[vaultId].status = VaultStatus.UNLOCKED;
                emit VaultUnlocked(vaultId, vaults[vaultId].owner);
            }
        }
    }

    // =============================================================
    //                     ADMIN FUNCTIONS
    // =============================================================

    /// @notice Set price feed for a token
    /// @param token Token address
    /// @param priceFeed Price feed address
    /// @param heartbeat Maximum time between updates
    /// @param decimals Price feed decimals
    function setPriceFeed(address token, address priceFeed, uint256 heartbeat, uint8 decimals) external onlyOwner {
        priceFeeds[token] = priceFeed;
        priceFeedHeartbeats[token] = heartbeat;
        priceFeedDecimals[token] = decimals;
        emit PriceFeedUpdated(token, priceFeed, heartbeat);
    }

    /// @notice Set token support
    /// @param token Token address
    /// @param supported Whether token is supported
    function setTokenSupport(address token, bool supported) external onlyOwner {
        supportedTokens[token] = supported;
        emit TokenSupportUpdated(token, supported);
    }

    /// @notice Pause/unpause contract
    function setPaused(bool paused) external onlyOwner {
        if (paused) {
            _pause();
        } else {
            _unpause();
        }
    }

    /// @notice Emergency function to withdraw stuck tokens
    function emergencyWithdrawToken(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).sendValue(amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    /// @notice Get vault details
    /// @param vaultId Vault ID
    /// @return vault Vault details
    function getVault(uint256 vaultId) external view returns (Vault memory vault) {
        return vaults[vaultId];
    }

    /// @notice Get user's vault IDs
    /// @param owner Owner address
    /// @return vaultIds Array of vault IDs
    function getUserVaults(address owner) external view returns (uint256[] memory vaultIds) {
        return ownerVaults[owner];
    }

    /// @notice Get total number of vaults
    /// @return total Total vault count
    function getTotalVaults() external view returns (uint256 total) {
        return nextVaultId - 1;
    }

    /// @notice Check if address has emergency penalty
    /// @param user User address
    /// @return penalty Emergency penalty details
    function getEmergencyPenalty(address user) external view returns (EmergencyPenalty memory penalty) {
        return emergencyPenalties[user];
    }

    /// @notice Receive function for native token deposits
    receive() external payable {
        // Allow receiving native tokens
    }
}