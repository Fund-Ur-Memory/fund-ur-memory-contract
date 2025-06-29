// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ICipherVault Interface
/// @notice Interface for the Cipher Vault contract
/// @dev This interface defines all external functions for easy integration
interface ICipherVault {

    // =============================================================
    //                           TYPES
    // =============================================================

    enum ConditionType {
        TIME_ONLY,
        PRICE_ONLY,
        TIME_OR_PRICE,
        TIME_AND_PRICE
    }

    enum VaultStatus {
        ACTIVE,
        UNLOCKED,
        WITHDRAWN,
        EMERGENCY
    }

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

    struct EmergencyPenalty {
        uint256 amount;
        uint256 penaltyTime;
        bool claimed;
    }

    // =============================================================
    //                           EVENTS
    // =============================================================

    event VaultCreated(
        uint256 indexed vaultId,
        address indexed owner,
        address indexed token,
        uint256 amount,
        ConditionType conditionType,
        uint256 unlockTime,
        uint256 targetPrice
    );

    event VaultUnlocked(uint256 indexed vaultId, string reason);
    event VaultWithdrawn(uint256 indexed vaultId, address indexed owner, uint256 amount);
    event EmergencyExecuted(uint256 indexed vaultId, address indexed owner, uint256 amount, uint256 penalty);
    event PenaltyClaimed(address indexed user, uint256 amount);
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);
    event TokenSupportUpdated(address indexed token, bool supported);

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
    //                      VAULT CREATION
    // =============================================================

    /// @notice Create a new vault with time-only condition
    function createTimeVault(
        address _token,
        uint256 _amount,
        uint256 _unlockTime
    ) external payable returns (uint256 vaultId);

    /// @notice Create a new vault with price-only condition
    function createPriceVault(
        address _token,
        uint256 _amount,
        uint256 _targetPrice
    ) external payable returns (uint256 vaultId);

    /// @notice Create a new vault with time OR price condition
    function createTimeOrPriceVault(
        address _token,
        uint256 _amount,
        uint256 _unlockTime,
        uint256 _targetPrice
    ) external payable returns (uint256 vaultId);

    /// @notice Create a new vault with time AND price condition
    function createTimeAndPriceVault(
        address _token,
        uint256 _amount,
        uint256 _unlockTime,
        uint256 _targetPrice
    ) external payable returns (uint256 vaultId);

    // =============================================================
    //                      VAULT OPERATIONS
    // =============================================================

    /// @notice Check if vault conditions are met and unlock if so
    function checkAndUnlockVault(uint256 _vaultId) external;

    /// @notice Withdraw assets from an unlocked vault
    function withdrawVault(uint256 _vaultId) external;

    /// @notice Execute emergency withdrawal immediately with penalty
    function executeEmergencyWithdrawal(uint256 _vaultId) external;

    /// @notice Claim penalty after 3 months delay
    function claimEmergencyPenalty() external;

    // =============================================================
    //                    CHAINLINK INTEGRATION
    // =============================================================

    /// @notice Get current price from Chainlink price feed
    function getCurrentPrice(address _token) external view returns (uint256 price);

    /// @notice Chainlink Automation compatible function to check if upkeep is needed
    function checkUpkeep(bytes calldata checkData)
        external
        view
        returns (bool upkeepNeeded, bytes memory performData);

    /// @notice Chainlink Automation compatible function to perform upkeep
    function performUpkeep(bytes calldata performData) external;

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    /// @notice Set price feed for a token (Chainlink integration)
    function setPriceFeed(address _token, address _priceFeed) external;

    /// @notice Add or remove token support
    function setTokenSupport(address _token, bool _supported) external;

    /// @notice Pause contract operations
    function pause() external;

    /// @notice Unpause contract operations
    function unpause() external;

    /// @notice Emergency function to recover stuck tokens (only penalties)
    function recoverPenalties(address _token, uint256 _amount) external;

    // =============================================================
    //                       VIEW FUNCTIONS
    // =============================================================

    /// @notice Get vault information
    function getVault(uint256 _vaultId) external view returns (Vault memory vault);

    /// @notice Get all vault IDs for an owner
    function getOwnerVaults(address _owner) external view returns (uint256[] memory vaultIds);

    /// @notice Check if vault conditions are met
    function checkConditions(uint256 _vaultId) external view returns (bool conditionsMet);

    /// @notice Get emergency penalty information for a user
    function getEmergencyPenalty(address _user)
        external
        view
        returns (EmergencyPenalty memory penalty);

    /// @notice Calculate emergency withdrawal penalty
    function calculateEmergencyPenalty(uint256 _amount) external pure returns (uint256 penalty);

    /// @notice Get contract statistics
    function getContractStats() external view returns (uint256 totalVaults, uint256 contractBalance);

    // =============================================================
    //                        CONSTANTS
    // =============================================================

    function EMERGENCY_PENALTY() external view returns (uint256);
    function PENALTY_CLAIM_DELAY() external view returns (uint256);
    function BASIS_POINTS() external view returns (uint256);
    function MIN_VAULT_AMOUNT() external view returns (uint256);

    // =============================================================
    //                         STORAGE
    // =============================================================

    function nextVaultId() external view returns (uint256);
    function vaults(uint256 vaultId) external view returns (
        address owner,
        address token,
        uint256 amount,
        uint256 unlockTime,
        uint256 targetPrice,
        ConditionType conditionType,
        VaultStatus status,
        uint256 createdAt,
        uint256 emergencyInitiated
    );
    function emergencyPenalties(address user) external view returns (
        uint256 amount,
        uint256 penaltyTime,
        bool claimed
    );
    function priceFeeds(address token) external view returns (address);
    function supportedTokens(address token) external view returns (bool);
    function owner() external view returns (address);
}