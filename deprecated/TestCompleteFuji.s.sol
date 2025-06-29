// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FUMVault.sol";

/// @title Test Complete Cipher Flow on Avalanche Fuji
contract TestCompleteFuji is Script {
    
    function run() external {
        address fumVaultAddress = vm.envAddress("FUM_VAULT_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("=== Testing Complete Cipher Flow on Avalanche Fuji ===");
        console.log("FUMVault Address:", fumVaultAddress);
        console.log("Chain ID:", block.chainid);
        
        FUMVault fumVault = FUMVault(payable(fumVaultAddress));
        
        // Test 1: Price Feeds
        console.log("\n1. Testing Price Feeds...");
        testPriceFeeds(fumVault);
        
        // Test 2: Create Vaults
        console.log("\n2. Creating Test Vaults...");
        vm.startBroadcast(deployerPrivateKey);
        uint256 timeVaultId = createTimeVault(fumVault);
        uint256 priceVaultId = createPriceVault(fumVault);
        vm.stopBroadcast();
        
        // Test 3: Check Conditions
        console.log("\n3. Testing Vault Conditions...");
        testVaultConditions(fumVault, timeVaultId, priceVaultId);
        
        // Test 4: Automation
        console.log("\n4. Testing Automation...");
        testAutomation(fumVault);
        
        // Test 5: Emergency Withdrawal
        console.log("\n5. Testing Emergency Withdrawal...");
        vm.startBroadcast(deployerPrivateKey);
        testEmergencyWithdrawal(fumVault, timeVaultId);
        vm.stopBroadcast();
        
        console.log("\n=== Test Complete ===");
        console.log("Next Steps:");
        console.log("1. Register Chainlink Automation at automation.chain.link");
        console.log("2. Fund upkeep with LINK tokens");
        console.log("3. Monitor automation at testnet.snowtrace.io");
    }
    
    function testPriceFeeds(FUMVault fumVault) internal view {
        console.log("Testing ETH/USD price feed...");
        try fumVault.getCurrentPrice(address(0)) returns (uint256 ethPrice) {
            console.log("ETH/USD Price:", ethPrice);
            console.log("   ETH Price in USD: $", ethPrice / 1e8);
            
            (uint256 price, uint256 updatedAt, bool isStale) = fumVault.getDetailedPrice(address(0));
            console.log("   Last updated:", updatedAt);
            console.log("   Is stale:", isStale);
            console.log("   Seconds since update:", block.timestamp - updatedAt);
        } catch {
            console.log("ETH/USD price feed failed");
        }
        
        // Test price feed info
        (address priceFeed, uint256 heartbeat, uint8 decimals) = fumVault.getPriceFeedInfo(address(0));
        console.log("Price feed address:", priceFeed);
        console.log("Heartbeat:", heartbeat, "seconds");
        console.log("Decimals:", decimals);
    }
    
    function createTimeVault(FUMVault fumVault) internal returns (uint256 vaultId) {
        console.log("Creating time-based vault...");
        
        uint256 unlockTime = block.timestamp + 1 hours; // 1 hour from now
        uint256 amount = 0.01 ether; // Small amount for testing
        
        vaultId = fumVault.createTimeVault{value: amount}(
            address(0), // ETH
            amount,
            unlockTime
        );
        
        console.log("Time vault created:");
        console.log("   Vault ID:", vaultId);
        console.log("   Amount:", amount);
        console.log("   Unlock time:", unlockTime);
        console.log("   Current time:", block.timestamp);
        console.log("   Time until unlock:", unlockTime - block.timestamp, "seconds");
        
        return vaultId;
    }
    
    function createPriceVault(FUMVault fumVault) internal returns (uint256 vaultId) {
        console.log("Creating price-based vault...");
        
        // Get current ETH price
        uint256 currentPrice = fumVault.getCurrentPrice(address(0));
        uint256 targetPrice = currentPrice * 105 / 100; // 5% higher
        uint256 amount = 0.01 ether;
        
        vaultId = fumVault.createPriceVault{value: amount}(
            address(0), // ETH
            amount,
            targetPrice
        );
        
        console.log("Price vault created:");
        console.log("   Vault ID:", vaultId);
        console.log("   Amount:", amount);
        console.log("   Current price: $", currentPrice / 1e8);
        console.log("   Target price: $", targetPrice / 1e8);
        console.log("   Price increase needed:", ((targetPrice - currentPrice) * 100) / currentPrice, "%");
        
        return vaultId;
    }
    
    function testVaultConditions(FUMVault fumVault, uint256 timeVaultId, uint256 priceVaultId) internal view {
        console.log("Checking vault conditions...");
        
        // Check time vault
        bool timeConditions = fumVault.checkConditions(timeVaultId);
        console.log("Time vault conditions met:", timeConditions);
        
        // Check price vault
        bool priceConditions = fumVault.checkConditions(priceVaultId);
        console.log("Price vault conditions met:", priceConditions);
        
        // Get vault details
        FUMVault.Vault memory timeVault = fumVault.getVault(timeVaultId);
        FUMVault.Vault memory priceVault = fumVault.getVault(priceVaultId);
        
        console.log("Time vault status:", uint256(timeVault.status));
        console.log("Price vault status:", uint256(priceVault.status));
    }
    
    function testAutomation(FUMVault fumVault) internal view {
        console.log("Testing automation functions...");
        
        // Test checkUpkeep
        try fumVault.checkUpkeep("") returns (bool upkeepNeeded, bytes memory performData) {
            console.log("Upkeep needed:", upkeepNeeded);
            
            if (upkeepNeeded) {
                uint256[] memory vaultIds = abi.decode(performData, (uint256[]));
                console.log("Vaults ready to unlock:", vaultIds.length);
                for (uint256 i = 0; i < vaultIds.length && i < 3; i++) {
                    console.log("   Vault ID:", vaultIds[i]);
                }
            } else {
                console.log("No vaults ready for unlock");
            }
        } catch {
            console.log("checkUpkeep failed");
        }
        
        // Check automation config
        uint256 checkInterval = fumVault.checkInterval();
        uint256 lastCheck = fumVault.lastCheckTimestamp();
        
        console.log("Check interval:", checkInterval, "seconds");
        console.log("Last check timestamp:", lastCheck);
        if (lastCheck > 0) {
            console.log("Time since last check:", block.timestamp - lastCheck, "seconds");
        }
    }
    
    function testEmergencyWithdrawal(FUMVault fumVault, uint256 vaultId) internal {
        console.log("Testing emergency withdrawal...");
        
        uint256 balanceBefore = address(this).balance;
        
        try fumVault.executeEmergencyWithdrawal(vaultId) {
            uint256 balanceAfter = address(this).balance;
            uint256 received = balanceAfter - balanceBefore;
            
            console.log("Emergency withdrawal successful:");
            console.log("   Amount received:", received);
            console.log("   Expected ~90% of vault amount");
            
            // Check penalty
            FUMVault.EmergencyPenalty memory penalty = fumVault.getEmergencyPenalty(address(this));
            console.log("   Penalty amount:", penalty.amount);
            console.log("   Penalty time:", penalty.penaltyTime);
            console.log("   Can claim after:", penalty.penaltyTime + fumVault.PENALTY_CLAIM_DELAY());
            
        } catch Error(string memory reason) {
            console.log("Emergency withdrawal failed:", reason);
        } catch {
            console.log("Emergency withdrawal failed with unknown error");
        }
    }
    
    // Receive function to accept ETH
    receive() external payable {}
}

/// @title Setup Automation Script
contract SetupAutomation is Script {
    
    function run() external {
        address fumVaultAddress = vm.envAddress("FUM_VAULT_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("=== Setting up Cipher for Automation ===");
        console.log("FUMVault Address:", fumVaultAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        FUMVault fumVault = FUMVault(payable(fumVaultAddress));
        
        // Set 5-second check interval for fast automation
        fumVault.setCheckInterval(5);
        console.log("Check interval set to 5 seconds");
        
        // Check current configuration
        uint256 interval = fumVault.checkInterval();
        console.log("Current check interval:", interval, "seconds");
        
        vm.stopBroadcast();
        
        console.log("\n=== Next Steps for Automation ===");
        console.log("1. Get LINK tokens from: https://faucets.chain.link/fuji");
        console.log("2. Register upkeep at: https://automation.chain.link/");
        console.log("3. Use these settings:");
        console.log("   - Trigger: Custom logic");
        console.log("   - Target contract:", fumVaultAddress);
        console.log("   - Gas limit: 500,000");
        console.log("   - Starting balance: 5 LINK");
        console.log("   - Check data: 0x (empty)");
    }
}

/// @title Monitor Automation Script
contract MonitorAutomation is Script {
    
    function run() external view {
        address fumVaultAddress = vm.envAddress("FUM_VAULT_ADDRESS");
        
        console.log("=== Monitoring Cipher Automation ===");
        console.log("FUMVault Address:", fumVaultAddress);
        console.log("Current time:", block.timestamp);
        
        FUMVault fumVault = FUMVault(payable(fumVaultAddress));
        
        // Check automation status
        (bool upkeepNeeded, bytes memory performData) = fumVault.checkUpkeep("");
        console.log("Upkeep needed:", upkeepNeeded);
        
        if (upkeepNeeded) {
            uint256[] memory vaultIds = abi.decode(performData, (uint256[]));
            console.log("Vaults ready to unlock:", vaultIds.length);
            
            for (uint256 i = 0; i < vaultIds.length; i++) {
                console.log("   Vault ID:", vaultIds[i]);
                
                FUMVault.Vault memory vault = fumVault.getVault(vaultIds[i]);
                console.log("   Owner:", vault.owner);
                console.log("   Amount:", vault.amount);
                console.log("   Status:", uint256(vault.status));
                
                bool conditions = fumVault.checkConditions(vaultIds[i]);
                console.log("   Conditions met:", conditions);
            }
        } else {
            console.log("No vaults ready to unlock");
        }
        
        // Check contract stats
        (uint256 totalVaults, uint256 contractBalance) = fumVault.getContractStats();
        console.log("Total vaults:", totalVaults);
        console.log("Contract balance:", contractBalance);
        
        // Check automation config
        uint256 checkInterval = fumVault.checkInterval();
        uint256 lastCheck = fumVault.lastCheckTimestamp();
        
        console.log("Check interval:", checkInterval, "seconds");
        console.log("Last automation check:", lastCheck);
        
        if (lastCheck > 0) {
            uint256 timeSinceCheck = block.timestamp - lastCheck;
            console.log("Time since last check:", timeSinceCheck, "seconds");
            
            if (timeSinceCheck > checkInterval) {
                console.log("Ready for next automation check");
            } else {
                console.log("Waiting for next check in:", checkInterval - timeSinceCheck, "seconds");
            }
        } else {
            console.log("No automation checks performed yet");
        }
    }
}
