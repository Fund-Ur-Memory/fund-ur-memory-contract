// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/FUMVault.sol";
import "@chainlink/contracts/v0.8/tests/MockV3Aggregator.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Mock ERC20 Token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18); // Mint 1M tokens
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title Comprehensive FUMVault Tests
contract FUMVaultTest is Test {
    FUMVault public fumVault;
    MockV3Aggregator public ethPriceFeed;
    MockV3Aggregator public btcPriceFeed;
    MockERC20 public mockToken;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public automationRegistry = address(0x4);

    // Price feed constants
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_INITIAL_PRICE = 2000 * 10**8; // $2000
    int256 public constant BTC_INITIAL_PRICE = 50000 * 10**8; // $50000

    // Test constants
    uint256 public constant VAULT_AMOUNT = 1 ether;
    uint256 public constant TOKEN_AMOUNT = 1000 * 10**18;

    event VaultCreated(
        uint256 indexed vaultId,
        address indexed owner,
        address indexed token,
        uint256 amount,
        FUMVault.ConditionType conditionType,
        uint256 unlockTime,
        uint256 targetPrice
    );

    event VaultUnlocked(uint256 indexed vaultId, string reason);
    event BatchUpkeepPerformed(uint256 totalChecked, uint256 successfulUnlocks);

    function setUp() public {
        // Set up accounts
        vm.startPrank(owner);

        // Deploy mock price feeds
        ethPriceFeed = new MockV3Aggregator(DECIMALS, ETH_INITIAL_PRICE);
        btcPriceFeed = new MockV3Aggregator(DECIMALS, BTC_INITIAL_PRICE);

        // Deploy mock token
        mockToken = new MockERC20("Mock Token", "MOCK");

        // Deploy FUMVault
        fumVault = new FUMVault(owner);

        // Set up price feeds
        fumVault.setPriceFeed(address(0), address(ethPriceFeed), 3600); // ETH with 1 hour heartbeat
        fumVault.setPriceFeed(address(mockToken), address(btcPriceFeed), 3600); // Mock token with BTC price

        // Add token support
        fumVault.setTokenSupport(address(mockToken), true);

        vm.stopPrank();

        // Fund test accounts
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);

        // Give tokens to users
        vm.startPrank(owner);
        mockToken.mint(user1, TOKEN_AMOUNT);
        mockToken.mint(user2, TOKEN_AMOUNT);
        vm.stopPrank();
    }

    // =============================================================
    //                    BASIC FUNCTIONALITY TESTS
    // =============================================================

    function testDeployment() public {
        assertEq(fumVault.owner(), owner);
        assertEq(fumVault.nextVaultId(), 1);
        assertTrue(fumVault.supportedTokens(address(0))); // ETH should be supported
        assertTrue(fumVault.supportedTokens(address(mockToken)));
    }

    function testPriceFeedSetup() public {
        assertEq(fumVault.priceFeeds(address(0)), address(ethPriceFeed));
        assertEq(fumVault.priceFeeds(address(mockToken)), address(btcPriceFeed));

        (address priceFeed, uint256 heartbeat, uint8 decimals) = fumVault.getPriceFeedInfo(address(0));
        assertEq(priceFeed, address(ethPriceFeed));
        assertEq(heartbeat, 3600);
        assertEq(decimals, DECIMALS);
    }

    function testGetCurrentPrice() public {
        uint256 ethPrice = fumVault.getCurrentPrice(address(0));
        assertEq(ethPrice, uint256(ETH_INITIAL_PRICE));

        uint256 tokenPrice = fumVault.getCurrentPrice(address(mockToken));
        assertEq(tokenPrice, uint256(BTC_INITIAL_PRICE));
    }

    function testGetDetailedPrice() public {
        (uint256 price, uint256 updatedAt, bool isStale) = fumVault.getDetailedPrice(address(0));
        assertEq(price, uint256(ETH_INITIAL_PRICE));
        assertGt(updatedAt, 0);
        assertFalse(isStale);
    }

    // =============================================================
    //                    VAULT CREATION TESTS
    // =============================================================

    function testCreateTimeVault() public {
        vm.startPrank(user1);

        uint256 unlockTime = block.timestamp + 1 days;

        vm.expectEmit(true, true, true, true);
        emit VaultCreated(1, user1, address(0), VAULT_AMOUNT, FUMVault.ConditionType.TIME_ONLY, unlockTime, 0);

        uint256 vaultId = fumVault.createTimeVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            unlockTime
        );

        assertEq(vaultId, 1);

        FUMVault.Vault memory vault = fumVault.getVault(vaultId);
        assertEq(vault.owner, user1);
        assertEq(vault.token, address(0));
        assertEq(vault.amount, VAULT_AMOUNT);
        assertEq(vault.unlockTime, unlockTime);
        assertEq(uint256(vault.conditionType), uint256(FUMVault.ConditionType.TIME_ONLY));
        assertEq(uint256(vault.status), uint256(FUMVault.VaultStatus.ACTIVE));

        vm.stopPrank();
    }

    function testCreatePriceVault() public {
        vm.startPrank(user1);

        uint256 targetPrice = 2500 * 10**8; // $2500

        vm.expectEmit(true, true, true, true);
        emit VaultCreated(1, user1, address(0), VAULT_AMOUNT, FUMVault.ConditionType.PRICE_ONLY, 0, targetPrice);

        uint256 vaultId = fumVault.createPriceVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            targetPrice
        );

        assertEq(vaultId, 1);

        FUMVault.Vault memory vault = fumVault.getVault(vaultId);
        assertEq(vault.targetPrice, targetPrice);
        assertEq(uint256(vault.conditionType), uint256(FUMVault.ConditionType.PRICE_ONLY));

        vm.stopPrank();
    }

    function testCreateTimeOrPriceVault() public {
        vm.startPrank(user1);

        uint256 unlockTime = block.timestamp + 1 days;
        uint256 targetPrice = 2500 * 10**8;

        uint256 vaultId = fumVault.createTimeOrPriceVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            unlockTime,
            targetPrice
        );

        FUMVault.Vault memory vault = fumVault.getVault(vaultId);
        assertEq(uint256(vault.conditionType), uint256(FUMVault.ConditionType.TIME_OR_PRICE));

        vm.stopPrank();
    }

    function testCreateTimeAndPriceVault() public {
        vm.startPrank(user1);

        uint256 unlockTime = block.timestamp + 1 days;
        uint256 targetPrice = 2500 * 10**8;

        uint256 vaultId = fumVault.createTimeAndPriceVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            unlockTime,
            targetPrice
        );

        FUMVault.Vault memory vault = fumVault.getVault(vaultId);
        assertEq(uint256(vault.conditionType), uint256(FUMVault.ConditionType.TIME_AND_PRICE));

        vm.stopPrank();
    }

    function testCreateTokenVault() public {
        vm.startPrank(user1);

        // Approve token transfer
        mockToken.approve(address(fumVault), TOKEN_AMOUNT);

        uint256 unlockTime = block.timestamp + 1 days;

        uint256 vaultId = fumVault.createTimeVault(
            address(mockToken),
            TOKEN_AMOUNT,
            unlockTime
        );

        FUMVault.Vault memory vault = fumVault.getVault(vaultId);
        assertEq(vault.token, address(mockToken));
        assertEq(vault.amount, TOKEN_AMOUNT);

        // Check token balance
        assertEq(mockToken.balanceOf(address(fumVault)), TOKEN_AMOUNT);

        vm.stopPrank();
    }

    // =============================================================
    //                    CONDITION CHECKING TESTS
    // =============================================================

    function testTimeConditionMet() public {
        vm.startPrank(user1);

        uint256 unlockTime = block.timestamp + 1 hours;
        uint256 vaultId = fumVault.createTimeVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            unlockTime
        );

        // Initially conditions not met
        assertFalse(fumVault.checkConditions(vaultId));

        // Fast forward time
        vm.warp(unlockTime + 1);

        // Now conditions should be met
        assertTrue(fumVault.checkConditions(vaultId));

        vm.stopPrank();
    }

    function testPriceConditionMet() public {
        vm.startPrank(user1);

        uint256 targetPrice = 2500 * 10**8; // $2500
        uint256 vaultId = fumVault.createPriceVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            targetPrice
        );

        // Initially conditions not met (price is $2000)
        assertFalse(fumVault.checkConditions(vaultId));

        vm.stopPrank();

        // Update price to meet condition
        vm.startPrank(owner);
        ethPriceFeed.updateAnswer(int256(targetPrice));
        vm.stopPrank();

        // Now conditions should be met
        assertTrue(fumVault.checkConditions(vaultId));
    }

    function testCheckIntervalControl() public {
        // Test default interval
        assertEq(fumVault.checkInterval(), 10);

        // Create vault
        vm.startPrank(user1);
        uint256 unlockTime = block.timestamp + 1 hours;
        uint256 vaultId = fumVault.createTimeVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            unlockTime
        );
        vm.stopPrank();

        // Fast forward time to meet condition
        vm.warp(unlockTime + 1);

        // First check should work (no previous timestamp)
        bytes memory checkData = abi.encode(1, 10, 50);
        (bool upkeepNeeded, bytes memory performData) = fumVault.checkUpkeep(checkData);
        assertTrue(upkeepNeeded);

        // Simulate performUpkeep to update timestamp
        fumVault.performUpkeep(performData);

        // Immediate second check should fail (interval not passed)
        (upkeepNeeded, ) = fumVault.checkUpkeep(checkData);
        assertFalse(upkeepNeeded);

        // Fast forward 5 seconds (less than 10 second interval)
        vm.warp(block.timestamp + 5);
        (upkeepNeeded, ) = fumVault.checkUpkeep(checkData);
        assertFalse(upkeepNeeded);

        // Fast forward 11 seconds total (more than 10 second interval)
        vm.warp(block.timestamp + 6);
        (upkeepNeeded, ) = fumVault.checkUpkeep(checkData);
        // Should be false because vault is already unlocked, but interval check passed
    }

    function testSetCheckInterval() public {
        vm.startPrank(owner);

        // Test setting 5 second interval
        vm.expectEmit(false, false, false, true);
        emit CheckIntervalUpdated(5);
        fumVault.setCheckInterval(5);
        assertEq(fumVault.checkInterval(), 5);

        // Test setting 10 second interval
        fumVault.setCheckInterval(10);
        assertEq(fumVault.checkInterval(), 10);

        // Test invalid intervals
        vm.expectRevert("Invalid interval");
        fumVault.setCheckInterval(4); // Too low

        vm.expectRevert("Invalid interval");
        fumVault.setCheckInterval(3601); // Too high

        vm.stopPrank();

        // Test non-owner cannot set
        vm.startPrank(user1);
        vm.expectRevert();
        fumVault.setCheckInterval(5);
        vm.stopPrank();
    }

    event CheckIntervalUpdated(uint256 newInterval);

    function testTimeOrPriceCondition() public {
        vm.startPrank(user1);

        uint256 unlockTime = block.timestamp + 1 days;
        uint256 targetPrice = 2500 * 10**8;
        uint256 vaultId = fumVault.createTimeOrPriceVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            unlockTime,
            targetPrice
        );

        // Initially conditions not met
        assertFalse(fumVault.checkConditions(vaultId));

        vm.stopPrank();

        // Test price condition
        vm.startPrank(owner);
        ethPriceFeed.updateAnswer(int256(targetPrice));
        vm.stopPrank();

        assertTrue(fumVault.checkConditions(vaultId));

        // Reset price and test time condition
        vm.startPrank(owner);
        ethPriceFeed.updateAnswer(ETH_INITIAL_PRICE);
        vm.stopPrank();

        assertFalse(fumVault.checkConditions(vaultId));

        // Fast forward time
        vm.warp(unlockTime + 1);
        assertTrue(fumVault.checkConditions(vaultId));
    }

    function testTimeAndPriceCondition() public {
        vm.startPrank(user1);

        uint256 unlockTime = block.timestamp + 1 days;
        uint256 targetPrice = 2500 * 10**8;
        uint256 vaultId = fumVault.createTimeAndPriceVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            unlockTime,
            targetPrice
        );

        // Initially conditions not met
        assertFalse(fumVault.checkConditions(vaultId));

        vm.stopPrank();

        // Test only price condition met
        vm.startPrank(owner);
        ethPriceFeed.updateAnswer(int256(targetPrice));
        vm.stopPrank();

        assertFalse(fumVault.checkConditions(vaultId)); // Still need time

        // Test only time condition met
        vm.startPrank(owner);
        ethPriceFeed.updateAnswer(ETH_INITIAL_PRICE);
        vm.stopPrank();

        vm.warp(unlockTime + 1);
        assertFalse(fumVault.checkConditions(vaultId)); // Still need price

        // Test both conditions met
        vm.startPrank(owner);
        ethPriceFeed.updateAnswer(int256(targetPrice));
        vm.stopPrank();

        assertTrue(fumVault.checkConditions(vaultId));
    }

    // =============================================================
    //                    VAULT OPERATIONS TESTS
    // =============================================================

    function testWithdrawVault() public {
        vm.startPrank(user1);

        uint256 unlockTime = block.timestamp + 1 hours;
        uint256 vaultId = fumVault.createTimeVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            unlockTime
        );

        uint256 balanceBefore = user1.balance;

        // Try to withdraw before unlock (should fail)
        vm.expectRevert(FUMVault.ConditionsNotMet.selector);
        fumVault.withdrawVault(vaultId);

        // Fast forward time
        vm.warp(unlockTime + 1);

        // Now withdrawal should work
        fumVault.withdrawVault(vaultId);

        // Check balance increased
        assertEq(user1.balance, balanceBefore + VAULT_AMOUNT);

        // Check vault status
        FUMVault.Vault memory vault = fumVault.getVault(vaultId);
        assertEq(uint256(vault.status), uint256(FUMVault.VaultStatus.WITHDRAWN));
        assertEq(vault.amount, 0);

        vm.stopPrank();
    }

    function testEmergencyWithdrawal() public {
        vm.startPrank(user1);

        uint256 unlockTime = block.timestamp + 1 days;
        uint256 vaultId = fumVault.createTimeVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            unlockTime
        );

        uint256 balanceBefore = user1.balance;

        // Execute emergency withdrawal immediately (no delay)
        fumVault.executeEmergencyWithdrawal(vaultId);

        // Check vault status
        FUMVault.Vault memory vault = fumVault.getVault(vaultId);
        assertEq(uint256(vault.status), uint256(FUMVault.VaultStatus.WITHDRAWN));

        // Check balance (should be less due to penalty)
        uint256 expectedAmount = VAULT_AMOUNT - (VAULT_AMOUNT * fumVault.EMERGENCY_PENALTY() / fumVault.BASIS_POINTS());
        assertEq(user1.balance, balanceBefore + expectedAmount);

        // Check penalty is stored for user
        FUMVault.EmergencyPenalty memory penalty = fumVault.getEmergencyPenalty(user1);
        uint256 expectedPenalty = (VAULT_AMOUNT * fumVault.EMERGENCY_PENALTY() / fumVault.BASIS_POINTS());
        assertEq(penalty.amount, expectedPenalty);
        assertFalse(penalty.claimed);

        vm.stopPrank();
    }

    function testClaimEmergencyPenalty() public {
        vm.startPrank(user1);

        uint256 unlockTime = block.timestamp + 1 days;
        uint256 vaultId = fumVault.createTimeVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            unlockTime
        );

        // Execute emergency withdrawal
        fumVault.executeEmergencyWithdrawal(vaultId);

        // Try to claim penalty immediately (should fail)
        vm.expectRevert(FUMVault.PenaltyClaimDelayNotPassed.selector);
        fumVault.claimEmergencyPenalty();

        // Fast forward 3 months
        vm.warp(block.timestamp + fumVault.PENALTY_CLAIM_DELAY() + 1);

        uint256 balanceBefore = user1.balance;

        // Claim penalty
        fumVault.claimEmergencyPenalty();

        // Check penalty was returned
        uint256 expectedPenalty = (VAULT_AMOUNT * fumVault.EMERGENCY_PENALTY() / fumVault.BASIS_POINTS());
        assertEq(user1.balance, balanceBefore + expectedPenalty);

        // Check penalty is marked as claimed
        FUMVault.EmergencyPenalty memory penalty = fumVault.getEmergencyPenalty(user1);
        assertTrue(penalty.claimed);
        assertEq(penalty.amount, 0);

        vm.stopPrank();
    }

    // =============================================================
    //                    CHAINLINK AUTOMATION TESTS
    // =============================================================

    function testCheckUpkeepNoVaults() public {
        bytes memory checkData = abi.encode(1, 10, 50);
        (bool upkeepNeeded, bytes memory performData) = fumVault.checkUpkeep(checkData);

        assertFalse(upkeepNeeded);
        assertEq(performData.length, 0);
    }

    function testCheckUpkeepWithReadyVaults() public {
        // Create multiple vaults
        vm.startPrank(user1);

        uint256 unlockTime = block.timestamp + 1 hours;
        uint256 vaultId1 = fumVault.createTimeVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            unlockTime
        );

        uint256 vaultId2 = fumVault.createTimeVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            unlockTime
        );

        vm.stopPrank();

        // Initially no upkeep needed
        bytes memory checkData = abi.encode(1, 10, 50);
        (bool upkeepNeeded, bytes memory performData) = fumVault.checkUpkeep(checkData);
        assertFalse(upkeepNeeded);

        // Fast forward time
        vm.warp(unlockTime + 1);

        // Now upkeep should be needed
        (upkeepNeeded, performData) = fumVault.checkUpkeep(checkData);
        assertTrue(upkeepNeeded);

        uint256[] memory readyVaults = abi.decode(performData, (uint256[]));
        assertEq(readyVaults.length, 2);
        assertEq(readyVaults[0], vaultId1);
        assertEq(readyVaults[1], vaultId2);
    }

    function testPerformUpkeep() public {
        // Create vault
        vm.startPrank(user1);

        uint256 unlockTime = block.timestamp + 1 hours;
        uint256 vaultId = fumVault.createTimeVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            unlockTime
        );

        vm.stopPrank();

        // Fast forward time
        vm.warp(unlockTime + 1);

        // Prepare perform data
        uint256[] memory vaultIds = new uint256[](1);
        vaultIds[0] = vaultId;
        bytes memory performData = abi.encode(vaultIds);

        // Expect events
        vm.expectEmit(true, false, false, true);
        emit VaultUnlocked(vaultId, "Automated unlock");

        vm.expectEmit(false, false, false, true);
        emit BatchUpkeepPerformed(1, 1);

        // Perform upkeep
        fumVault.performUpkeep(performData);

        // Check vault status
        FUMVault.Vault memory vault = fumVault.getVault(vaultId);
        assertEq(uint256(vault.status), uint256(FUMVault.VaultStatus.UNLOCKED));
    }

    // =============================================================
    //                    PRICE FEED TESTS
    // =============================================================

    function testStalePriceFeed() public {
        // Fast forward time to make price stale
        vm.warp(block.timestamp + 7200); // 2 hours

        vm.expectRevert(FUMVault.InvalidPriceFeed.selector);
        fumVault.getCurrentPrice(address(0));
    }

    function testInvalidPriceFeed() public {
        vm.startPrank(owner);

        // Set invalid price feed
        vm.expectRevert(FUMVault.InvalidPriceFeed.selector);
        fumVault.setPriceFeed(address(0), address(0), 3600);

        vm.stopPrank();
    }

    function testPriceFeedWithDifferentDecimals() public {
        vm.startPrank(owner);

        // Create price feed with 18 decimals
        MockV3Aggregator priceFeed18 = new MockV3Aggregator(18, 2000 * 10**18);
        fumVault.setPriceFeed(address(mockToken), address(priceFeed18), 3600);

        vm.stopPrank();

        // Price should be normalized to 8 decimals
        uint256 price = fumVault.getCurrentPrice(address(mockToken));
        assertEq(price, 2000 * 10**8);
    }

    // =============================================================
    //                    ERROR CONDITION TESTS
    // =============================================================

    function testCreateVaultInvalidTime() public {
        vm.startPrank(user1);

        vm.expectRevert(FUMVault.InvalidTimeCondition.selector);
        fumVault.createTimeVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            block.timestamp - 1 // Past time
        );

        vm.stopPrank();
    }

    function testCreateVaultUnsupportedToken() public {
        vm.startPrank(user1);

        address unsupportedToken = address(0x999);

        vm.expectRevert(FUMVault.TokenNotSupported.selector);
        fumVault.createTimeVault(
            unsupportedToken,
            TOKEN_AMOUNT,
            block.timestamp + 1 days
        );

        vm.stopPrank();
    }

    function testCreatePriceVaultNoPriceFeed() public {
        vm.startPrank(owner);

        // Add token support but no price feed
        address newToken = address(0x888);
        fumVault.setTokenSupport(newToken, true);

        vm.stopPrank();

        vm.startPrank(user1);

        vm.expectRevert(FUMVault.PriceFeedNotSet.selector);
        fumVault.createPriceVault(
            newToken,
            TOKEN_AMOUNT,
            2500 * 10**8
        );

        vm.stopPrank();
    }

    function testWithdrawNotOwner() public {
        vm.startPrank(user1);

        uint256 unlockTime = block.timestamp + 1 hours;
        uint256 vaultId = fumVault.createTimeVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            unlockTime
        );

        vm.stopPrank();

        // Fast forward time
        vm.warp(unlockTime + 1);

        // Try to withdraw as different user
        vm.startPrank(user2);

        vm.expectRevert(FUMVault.NotVaultOwner.selector);
        fumVault.withdrawVault(vaultId);

        vm.stopPrank();
    }

    // =============================================================
    //                    INTEGRATION TESTS
    // =============================================================

    function testFullWorkflowTimeVault() public {
        vm.startPrank(user1);

        uint256 unlockTime = block.timestamp + 1 days;
        uint256 balanceBefore = user1.balance;

        // Create vault
        uint256 vaultId = fumVault.createTimeVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            unlockTime
        );

        // Check initial state
        assertFalse(fumVault.checkConditions(vaultId));

        // Fast forward time
        vm.warp(unlockTime + 1);

        // Check conditions met
        assertTrue(fumVault.checkConditions(vaultId));

        // Withdraw
        fumVault.withdrawVault(vaultId);

        // Verify final state
        assertEq(user1.balance, balanceBefore);

        FUMVault.Vault memory vault = fumVault.getVault(vaultId);
        assertEq(uint256(vault.status), uint256(FUMVault.VaultStatus.WITHDRAWN));

        vm.stopPrank();
    }

    function testFullWorkflowPriceVault() public {
        vm.startPrank(user1);

        uint256 targetPrice = 2500 * 10**8;
        uint256 balanceBefore = user1.balance;

        // Create vault
        uint256 vaultId = fumVault.createPriceVault{value: VAULT_AMOUNT}(
            address(0),
            VAULT_AMOUNT,
            targetPrice
        );

        vm.stopPrank();

        // Update price to trigger condition
        vm.startPrank(owner);
        ethPriceFeed.updateAnswer(int256(targetPrice));
        vm.stopPrank();

        // Check conditions met
        assertTrue(fumVault.checkConditions(vaultId));

        // Withdraw
        vm.startPrank(user1);
        fumVault.withdrawVault(vaultId);

        // Verify final state
        assertEq(user1.balance, balanceBefore);

        vm.stopPrank();
    }
}
