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

/// @title FUMVault - Fund Ur Memory/Money Commitment Vault
/// @notice A DeFi protocol for automated asset management using commitment contracts
/// @dev MVP version with Chainlink Price Feeds and Automation integration
contract FUMVault is ReentrancyGuard, Pausable, Ownable, AutomationCompatibleInterface {
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

    /// @notice Last check timestamp for automation
    uint256 public lastCheckTimestamp;

    /// @notice Check interval for automation (default 10 seconds)
    uint256 public checkInterval = 10;

    // =============================================================
    //                           EVENTS
    // =============================================================

    /// @notice Emitted when a new vault is created
    event VaultCreated(
        uint256 indexed vaultId,
        address indexed owner,
        address indexed token,
        uint256 amount,
        ConditionType conditionType,
        uint256 unlockTime,
        uint256 targetPrice
    );

    /// @notice Emitted when a vault is unlocked
    event VaultUnlocked(uint256 indexed vaultId, string reason);

    /// @notice Emitted when assets are withdrawn from a vault
    event VaultWithdrawn(uint256 indexed vaultId, address indexed owner, uint256 amount);

    /// @notice Emitted when emergency withdrawal is executed
    event EmergencyExecuted(uint256 indexed vaultId, address indexed owner, uint256 amount, uint256 penalty);

    /// @notice Emitted when penalty is claimed
    event PenaltyClaimed(address indexed user, uint256 amount);

    /// @notice Emitted when a price feed is updated
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);

    /// @notice Emitted when a token is added/removed from supported list
    event TokenSupportUpdated(address indexed token, bool supported);

    /// @notice Emitted when batch upkeep is performed
    event BatchUpkeepPerformed(uint256 totalChecked, uint256 successfulUnlocks);

    /// @notice Emitted when check interval is updated
    event CheckIntervalUpdated(uint256 newInterval);

    // =============================================================
    //                           ERRORS
    // =============================================================

    error InsufficientAmount();
    error InvalidCondition();
    error VaultNotFound();
    error NotVaultOwner();
    error VaultNotActive();
    error ConditionsNotMet();
    error PenaltyNotAvailable();
    error PenaltyAlreadyClaimed();
    error PenaltyClaimDelayNotPassed();
    error TokenNotSupported();
    error PriceFeedNotSet();
    error InvalidPriceFeed();
    error TransferFailed();
    error InvalidTimeCondition();
    error InvalidPriceCondition();

    // =============================================================
    //                        CONSTRUCTOR
    // =============================================================

    /// @notice Initialize the FUM Vault contract
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

    /// @notice Create a new vault with time-only condition
    /// @param _token Token address (address(0) for ETH)
    /// @param _amount Amount to lock
    /// @param _unlockTime Timestamp when vault unlocks
    /// @return vaultId The ID of the created vault
    function createTimeVault(
        address _token,
        uint256 _amount,
        uint256 _unlockTime
    ) external payable nonReentrant whenNotPaused returns (uint256 vaultId) {
        if (_unlockTime <= block.timestamp) revert InvalidTimeCondition();

        return _createVault(
            _token,
            _amount,
            _unlockTime,
            0, // No price target
            ConditionType.TIME_ONLY
        );
    }

    /// @notice Create a new vault with price-only condition
    /// @param _token Token address (address(0) for ETH)
    /// @param _amount Amount to lock
    /// @param _targetPrice Target price in USD (8 decimals)
    /// @return vaultId The ID of the created vault
    function createPriceVault(
        address _token,
        uint256 _amount,
        uint256 _targetPrice
    ) external payable nonReentrant whenNotPaused returns (uint256 vaultId) {
        if (_targetPrice == 0) revert InvalidPriceCondition();
        if (priceFeeds[_token] == address(0)) revert PriceFeedNotSet();

        return _createVault(
            _token,
            _amount,
            0, // No time condition
            _targetPrice,
            ConditionType.PRICE_ONLY
        );
    }

    /// @notice Create a new vault with combined time OR price condition
    /// @param _token Token address (address(0) for ETH)
    /// @param _amount Amount to lock
    /// @param _unlockTime Timestamp when vault unlocks
    /// @param _targetPrice Target price in USD (8 decimals)
    /// @return vaultId The ID of the created vault
    function createTimeOrPriceVault(
        address _token,
        uint256 _amount,
        uint256 _unlockTime,
        uint256 _targetPrice
    ) external payable nonReentrant whenNotPaused returns (uint256 vaultId) {
        if (_unlockTime <= block.timestamp) revert InvalidTimeCondition();
        if (_targetPrice == 0) revert InvalidPriceCondition();
        if (priceFeeds[_token] == address(0)) revert PriceFeedNotSet();

        return _createVault(
            _token,
            _amount,
            _unlockTime,
            _targetPrice,
            ConditionType.TIME_OR_PRICE
        );
    }

    /// @notice Create a new vault with combined time AND price condition
    /// @param _token Token address (address(0) for ETH)
    /// @param _amount Amount to lock
    /// @param _unlockTime Timestamp when vault unlocks
    /// @param _targetPrice Target price in USD (8 decimals)
    /// @return vaultId The ID of the created vault
    function createTimeAndPriceVault(
        address _token,
        uint256 _amount,
        uint256 _unlockTime,
        uint256 _targetPrice
    ) external payable nonReentrant whenNotPaused returns (uint256 vaultId) {
        if (_unlockTime <= block.timestamp) revert InvalidTimeCondition();
        if (_targetPrice == 0) revert InvalidPriceCondition();
        if (priceFeeds[_token] == address(0)) revert PriceFeedNotSet();

        return _createVault(
            _token,
            _amount,
            _unlockTime,
            _targetPrice,
            ConditionType.TIME_AND_PRICE
        );
    }

    // =============================================================
    //                    INTERNAL VAULT CREATION
    // =============================================================

    /// @notice Internal function to create a vault
    /// @param _token Token address
    /// @param _amount Amount to lock
    /// @param _unlockTime Unlock timestamp
    /// @param _targetPrice Target price
    /// @param _conditionType Condition type
    /// @return vaultId The created vault ID
    function _createVault(
        address _token,
        uint256 _amount,
        uint256 _unlockTime,
        uint256 _targetPrice,
        ConditionType _conditionType
    ) internal returns (uint256 vaultId) {
        // Validate token support
        if (!supportedTokens[_token]) revert TokenNotSupported();

        // Validate amount
        // if (_amount < MIN_VAULT_AMOUNT) revert InsufficientAmount();

        // Handle ETH vs ERC20 deposits
        if (_token == address(0)) {
            // ETH deposit
            if (msg.value != _amount) revert InsufficientAmount();
        } else {
            // ERC20 deposit
            if (msg.value != 0) revert InvalidCondition();
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }

        // Create vault
        vaultId = nextVaultId++;

        vaults[vaultId] = Vault({
            owner: msg.sender,
            token: _token,
            amount: _amount,
            unlockTime: _unlockTime,
            targetPrice: _targetPrice,
            conditionType: _conditionType,
            status: VaultStatus.ACTIVE,
            createdAt: block.timestamp,
            emergencyInitiated: 0
        });

        // Add to owner's vault list
        ownerVaults[msg.sender].push(vaultId);

        emit VaultCreated(
            vaultId,
            msg.sender,
            _token,
            _amount,
            _conditionType,
            _unlockTime,
            _targetPrice
        );
    }

    // =============================================================
    //                      VAULT OPERATIONS
    // =============================================================

    /// @notice Check if vault conditions are met and unlock if so
    /// @param _vaultId Vault ID to check
    /// @dev This function can be called by Chainlink Automation
    function checkAndUnlockVault(uint256 _vaultId) external {
        Vault storage vault = vaults[_vaultId];

        if (vault.owner == address(0)) revert VaultNotFound();
        if (vault.status != VaultStatus.ACTIVE) revert VaultNotActive();

        bool conditionsMet = _checkConditions(_vaultId);

        if (conditionsMet) {
            vault.status = VaultStatus.UNLOCKED;
            emit VaultUnlocked(_vaultId, "Conditions met");
        }
    }

    /// @notice Withdraw assets from an unlocked vault
    /// @param _vaultId Vault ID to withdraw from
    function withdrawVault(uint256 _vaultId) external nonReentrant {
        Vault storage vault = vaults[_vaultId];

        if (vault.owner == address(0)) revert VaultNotFound();
        if (vault.owner != msg.sender) revert NotVaultOwner();
        if (vault.status != VaultStatus.UNLOCKED) {
            // Try to unlock first
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

        // Transfer assets
        _transferAssets(vault.token, vault.owner, amount);

        emit VaultWithdrawn(_vaultId, vault.owner, amount);
    }

    /// @notice Execute emergency withdrawal immediately with 10% penalty
    /// @param _vaultId Vault ID for emergency withdrawal
    function executeEmergencyWithdrawal(uint256 _vaultId) external nonReentrant {
        Vault storage vault = vaults[_vaultId];

        if (vault.owner == address(0)) revert VaultNotFound();
        if (vault.owner != msg.sender) revert NotVaultOwner();
        if (vault.status != VaultStatus.ACTIVE) revert VaultNotActive();

        uint256 penalty = (vault.amount * EMERGENCY_PENALTY) / BASIS_POINTS;
        uint256 withdrawAmount = vault.amount - penalty;

        // Update vault status
        vault.status = VaultStatus.WITHDRAWN;
        vault.amount = 0;

        // Store penalty for user to claim after 3 months
        EmergencyPenalty storage userPenalty = emergencyPenalties[msg.sender];
        userPenalty.amount += penalty;
        userPenalty.penaltyTime = block.timestamp;
        userPenalty.claimed = false;

        // Transfer reduced amount (after penalty) to user immediately
        _transferAssets(vault.token, msg.sender, withdrawAmount);

        emit EmergencyExecuted(_vaultId, msg.sender, withdrawAmount, penalty);
    }

    /// @notice Claim penalty after 3 months delay
    function claimEmergencyPenalty() external nonReentrant {
        EmergencyPenalty storage penalty = emergencyPenalties[msg.sender];

        if (penalty.amount == 0) revert PenaltyNotAvailable();
        if (penalty.claimed) revert PenaltyAlreadyClaimed();
        if (block.timestamp < penalty.penaltyTime + PENALTY_CLAIM_DELAY) {
            revert PenaltyClaimDelayNotPassed();
        }

        uint256 claimAmount = penalty.amount;
        penalty.claimed = true;
        penalty.amount = 0;

        // Transfer penalty back to user (assuming ETH for now, can be extended for tokens)
        _transferAssets(address(0), msg.sender, claimAmount);

        emit PenaltyClaimed(msg.sender, claimAmount);
    }

    // =============================================================
    //                    CHAINLINK INTEGRATION
    // =============================================================

    /// @notice Get current price from Chainlink price feed with enhanced validation
    /// @param _token Token address to get price for
    /// @return price Current price in USD (normalized to 8 decimals)
    function getCurrentPrice(address _token) public view returns (uint256 price) {
        address priceFeedAddress = priceFeeds[_token];
        if (priceFeedAddress == address(0)) revert PriceFeedNotSet();

        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);

        try priceFeed.latestRoundData() returns (
            uint80 /* roundId */,
            int256 answer,
            uint256 /* startedAt */,
            uint256 updatedAt,
            uint80 /* answeredInRound */
        ) {
            // Validate round data (more lenient validation for testnet)
            if (answer <= 0) revert InvalidPriceFeed();
            if (updatedAt == 0) revert InvalidPriceFeed();

            // Check staleness using custom heartbeat or default
            uint256 heartbeat = priceFeedHeartbeats[_token];
            if (heartbeat == 0) heartbeat = MAX_PRICE_STALENESS;

            if (block.timestamp - updatedAt > heartbeat) revert InvalidPriceFeed();

            // Normalize price to 8 decimals
            uint8 feedDecimals = priceFeedDecimals[_token];
            if (feedDecimals == 0) {
                // Try to get decimals from the feed
                try priceFeed.decimals() returns (uint8 decimals) {
                    feedDecimals = decimals;
                } catch {
                    feedDecimals = 8; // Default to 8 decimals
                }
            }

            // Normalize to 8 decimals
            if (feedDecimals > 8) {
                return uint256(answer) / (10 ** (feedDecimals - 8));
            } else if (feedDecimals < 8) {
                return uint256(answer) * (10 ** (8 - feedDecimals));
            } else {
                return uint256(answer);
            }
        } catch {
            revert InvalidPriceFeed();
        }
    }

    /// @notice Check if vault conditions are met
    /// @param _vaultId Vault ID to check
    /// @return conditionsMet Whether conditions are satisfied
    function _checkConditions(uint256 _vaultId) internal view returns (bool conditionsMet) {
        Vault storage vault = vaults[_vaultId];

        bool timeConditionMet = vault.unlockTime > 0 && block.timestamp >= vault.unlockTime;
        bool priceConditionMet = false;

        if (vault.targetPrice > 0) {
            try this.getCurrentPrice(vault.token) returns (uint256 currentPrice) {
                priceConditionMet = currentPrice >= vault.targetPrice;
            } catch {
                // If price feed fails, price condition is not met
                priceConditionMet = false;
            }
        }

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
            // Transfer ERC20
            IERC20(_token).safeTransfer(_to, _amount);
        }
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    /// @notice Set price feed for a token with enhanced validation
    /// @param _token Token address
    /// @param _priceFeed Chainlink price feed address
    /// @param _heartbeat Maximum time between price updates (0 for default)
    function setPriceFeed(
        address _token,
        address _priceFeed,
        uint256 _heartbeat
    ) external onlyOwner {
        if (_priceFeed == address(0)) revert InvalidPriceFeed();

        // Validate the price feed by trying to get latest data
        AggregatorV3Interface feed = AggregatorV3Interface(_priceFeed);
        try feed.latestRoundData() returns (uint80, int256 answer, uint256, uint256, uint80) {
            if (answer <= 0) revert InvalidPriceFeed();
        } catch {
            revert InvalidPriceFeed();
        }

        // Try to get and store decimals
        try feed.decimals() returns (uint8 decimals) {
            priceFeedDecimals[_token] = decimals;
        } catch {
            priceFeedDecimals[_token] = 8; // Default to 8 decimals
        }

        priceFeeds[_token] = _priceFeed;
        if (_heartbeat > 0) {
            priceFeedHeartbeats[_token] = _heartbeat;
        }

        emit PriceFeedUpdated(_token, _priceFeed);
    }

    /// @notice Add or remove token support
    /// @param _token Token address
    /// @param _supported Whether token is supported
    function setTokenSupport(address _token, bool _supported) external onlyOwner {
        supportedTokens[_token] = _supported;
        emit TokenSupportUpdated(_token, _supported);
    }

    /// @notice Pause contract operations
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause contract operations
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Emergency function to recover stuck tokens (only penalties)
    /// @param _token Token address
    /// @param _amount Amount to recover
    function recoverPenalties(address _token, uint256 _amount) external onlyOwner {
        // Only allow recovery of penalty amounts, not user funds
        _transferAssets(_token, owner(), _amount);
    }

    /// @notice Set check interval for automation (5-10 seconds recommended)
    /// @param _interval Check interval in seconds
    function setCheckInterval(uint256 _interval) external onlyOwner {
        require(_interval >= 5 && _interval <= 3600, "Invalid interval"); // 5 seconds to 1 hour
        checkInterval = _interval;
        emit CheckIntervalUpdated(_interval);
    }

    // =============================================================
    //                       VIEW FUNCTIONS
    // =============================================================

    /// @notice Get vault information
    /// @param _vaultId Vault ID
    /// @return vault Vault data
    function getVault(uint256 _vaultId) external view returns (Vault memory vault) {
        return vaults[_vaultId];
    }

    /// @notice Get all vault IDs for an owner
    /// @param _owner Owner address
    /// @return vaultIds Array of vault IDs
    function getOwnerVaults(address _owner) external view returns (uint256[] memory vaultIds) {
        return ownerVaults[_owner];
    }

    /// @notice Check if vault conditions are met (external view)
    /// @param _vaultId Vault ID
    /// @return conditionsMet Whether conditions are satisfied
    function checkConditions(uint256 _vaultId) external view returns (bool conditionsMet) {
        return _checkConditions(_vaultId);
    }

    /// @notice Get emergency penalty information for a user
    /// @param _user User address
    /// @return penalty Emergency penalty data
    function getEmergencyPenalty(address _user)
        external
        view
        returns (EmergencyPenalty memory penalty)
    {
        return emergencyPenalties[_user];
    }

    /// @notice Calculate emergency withdrawal penalty
    /// @param _amount Vault amount
    /// @return penalty Penalty amount
    function calculateEmergencyPenalty(uint256 _amount) external pure returns (uint256 penalty) {
        return (_amount * EMERGENCY_PENALTY) / BASIS_POINTS;
    }

    /// @notice Get contract statistics
    /// @return totalVaults Total number of vaults created
    /// @return contractBalance ETH balance of contract
    function getContractStats() external view returns (uint256 totalVaults, uint256 contractBalance) {
        return (nextVaultId - 1, address(this).balance);
    }

    /// @notice Get price feed information for a token
    /// @param _token Token address
    /// @return priceFeed Price feed address
    /// @return heartbeat Price feed heartbeat
    /// @return decimals Price feed decimals
    function getPriceFeedInfo(address _token)
        external
        view
        returns (address priceFeed, uint256 heartbeat, uint8 decimals)
    {
        priceFeed = priceFeeds[_token];
        heartbeat = priceFeedHeartbeats[_token];
        if (heartbeat == 0) heartbeat = MAX_PRICE_STALENESS;
        decimals = priceFeedDecimals[_token];
        if (decimals == 0) decimals = 8;
    }

    /// @notice Get detailed price information for a token
    /// @param _token Token address
    /// @return price Current price (8 decimals)
    /// @return updatedAt Last update timestamp
    /// @return isStale Whether the price is stale
    function getDetailedPrice(address _token)
        external
        view
        returns (uint256 price, uint256 updatedAt, bool isStale)
    {
        address priceFeedAddress = priceFeeds[_token];
        if (priceFeedAddress == address(0)) {
            return (0, 0, true);
        }

        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);

        try priceFeed.latestRoundData() returns (
            uint80,
            int256 answer,
            uint256,
            uint256 _updatedAt,
            uint80
        ) {
            if (answer <= 0) {
                return (0, _updatedAt, true);
            }

            uint256 heartbeat = priceFeedHeartbeats[_token];
            if (heartbeat == 0) heartbeat = MAX_PRICE_STALENESS;

            isStale = block.timestamp - _updatedAt > heartbeat;
            updatedAt = _updatedAt;

            // Normalize price to 8 decimals
            uint8 feedDecimals = priceFeedDecimals[_token];
            if (feedDecimals == 0) feedDecimals = 8;

            if (feedDecimals > 8) {
                price = uint256(answer) / (10 ** (feedDecimals - 8));
            } else if (feedDecimals < 8) {
                price = uint256(answer) * (10 ** (8 - feedDecimals));
            } else {
                price = uint256(answer);
            }
        } catch {
            return (0, 0, true);
        }
    }

    // =============================================================
    //                    CHAINLINK AUTOMATION
    // =============================================================

    /// @notice Enhanced Chainlink Automation function to check if upkeep is needed
    /// @dev This function is called by Chainlink Automation nodes to determine if performUpkeep should be called
    ///
    /// HOW IT WORKS:
    /// 1. Chainlink nodes call this function periodically (every block or custom interval)
    /// 2. First checks if enough time has passed since last check (checkInterval)
    /// 3. Function scans through vault IDs to find vaults that meet unlock conditions
    /// 4. If any vaults are ready to unlock, returns true + vault IDs to unlock
    /// 5. If true, Chainlink automatically calls performUpkeep with the vault IDs
    /// 6. performUpkeep then unlocks those specific vaults
    ///
    /// PRICE CHECKING FREQUENCY:
    /// - checkInterval = 10 seconds (default) for frequent price monitoring
    /// - Can be set to 5-10 seconds for high-frequency checking
    /// - Note: Chainlink price feeds still update every 1 hour or 0.5% deviation
    ///
    /// @param checkData Encoded parameters: (startId, endId, maxVaults) - optional, uses defaults if empty
    /// @return upkeepNeeded Whether upkeep is needed (true = call performUpkeep)
    /// @return performData Data to pass to performUpkeep (encoded vault IDs to unlock)
    function checkUpkeep(bytes calldata checkData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        // Check if enough time has passed since last check
        if (block.timestamp < lastCheckTimestamp + checkInterval) {
            return (false, "");
        }
        (uint256 startId, uint256 endId, uint256 maxVaults) = checkData.length > 0
            ? abi.decode(checkData, (uint256, uint256, uint256))
            : (1, nextVaultId - 1, 50); // Default values

        if (endId >= nextVaultId) endId = nextVaultId - 1;
        if (maxVaults == 0) maxVaults = 50;

        uint256[] memory readyVaults = new uint256[](maxVaults);
        uint256 readyCount = 0;

        for (uint256 vaultId = startId; vaultId <= endId && readyCount < maxVaults; vaultId++) {
            Vault storage vault = vaults[vaultId];

            if (vault.owner != address(0) &&
                vault.status == VaultStatus.ACTIVE &&
                _checkConditions(vaultId)) {
                readyVaults[readyCount] = vaultId;
                readyCount++;
            }
        }

        if (readyCount > 0) {
            // Resize array to actual size
            uint256[] memory result = new uint256[](readyCount);
            for (uint256 i = 0; i < readyCount; i++) {
                result[i] = readyVaults[i];
            }
            return (true, abi.encode(result));
        }

        return (false, "");
    }

    /// @notice Enhanced Chainlink Automation function to perform upkeep
    /// @param performData Encoded vault IDs to unlock
    function performUpkeep(bytes calldata performData) external override {
        // Update last check timestamp for interval control
        lastCheckTimestamp = block.timestamp;

        uint256[] memory vaultIds = abi.decode(performData, (uint256[]));
        uint256 successCount = 0;

        for (uint256 i = 0; i < vaultIds.length; i++) {
            uint256 vaultId = vaultIds[i];
            Vault storage vault = vaults[vaultId];

            // Double-check conditions to prevent race conditions
            if (vault.owner != address(0) &&
                vault.status == VaultStatus.ACTIVE &&
                _checkConditions(vaultId)) {
                vault.status = VaultStatus.UNLOCKED;
                successCount++;
                emit VaultUnlocked(vaultId, "Automated unlock");
            }
        }

        // Emit batch processing event for monitoring
        emit BatchUpkeepPerformed(vaultIds.length, successCount);
    }

    // =============================================================
    //                        FALLBACK
    // =============================================================

    /// @notice Receive function to accept ETH deposits
    receive() external payable {
        // Allow ETH deposits for vault creation
    }
}