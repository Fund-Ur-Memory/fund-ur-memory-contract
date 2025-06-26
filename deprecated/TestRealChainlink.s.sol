// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FUMVault.sol";
import "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title Test Real Chainlink Integration
/// @notice Script to test deployed FUMVault with real Chainlink services
contract TestRealChainlink is Script {
    
    function run() external {
        // Get contract address from environment or use deployed address
        address fumVaultAddress = vm.envOr("FUM_VAULT_ADDRESS", address(0));
        
        if (fumVaultAddress == address(0)) {
            console.log("Please set FUM_VAULT_ADDRESS environment variable");
            return;
        }
        
        console.log("Testing FUMVault at:", fumVaultAddress);
        console.log("Chain ID:", block.chainid);
        
        FUMVault fumVault = FUMVault(payable(fumVaultAddress));
        
        // Test 1: Check price feeds
        console.log("\n=== Testing Price Feeds ===");
        testPriceFeeds(fumVault);
        
        // Test 2: Check automation
        console.log("\n=== Testing Automation ===");
        testAutomation(fumVault);
        
        // Test 3: Check contract configuration
        console.log("\n=== Testing Configuration ===");
        testConfiguration(fumVault);
        
        console.log("\n=== Test Complete ===");
    }
    
    function testPriceFeeds(FUMVault fumVault) internal view {
        // Test ETH/USD price feed
        try fumVault.getCurrentPrice(address(0)) returns (uint256 ethPrice) {
            console.log("[SUCCESS] ETH/USD Price:", ethPrice);
            console.log("ETH Price in USD:", ethPrice / 1e8);
            
            // Get detailed price info
            (uint256 price, uint256 updatedAt, bool isStale) = fumVault.getDetailedPrice(address(0));
            console.log("Last updated:", updatedAt);
            console.log("Is stale:", isStale);
            console.log("Time since update:", block.timestamp - updatedAt, "seconds");
            
        } catch Error(string memory reason) {
            console.log("[ERROR] ETH/USD Price Feed failed:", reason);
        } catch {
            console.log("[ERROR] ETH/USD Price Feed failed with unknown error");
        }
        
        // Test price feed info
        try fumVault.getPriceFeedInfo(address(0)) returns (
            address priceFeed, 
            uint256 heartbeat, 
            uint8 decimals
        ) {
            console.log("Price feed address:", priceFeed);
            console.log("Heartbeat:", heartbeat, "seconds");
            console.log("Decimals:", decimals);
            
            // Test the price feed directly
            if (priceFeed != address(0)) {
                AggregatorV3Interface feed = AggregatorV3Interface(priceFeed);
                try feed.latestRoundData() returns (
                    uint80 roundId,
                    int256 answer,
                    uint256 startedAt,
                    uint256 updatedAt,
                    uint80 answeredInRound
                ) {
                    console.log("[SUCCESS] Direct price feed call:");
                    console.log("  Round ID:", roundId);
                    console.log("  Answer:", uint256(answer));
                    console.log("  Updated at:", updatedAt);
                } catch {
                    console.log("[ERROR] Direct price feed call failed");
                }
            }
        } catch {
            console.log("[ERROR] Could not get price feed info");
        }
    }
    
    function testAutomation(FUMVault fumVault) internal view {
        // Test checkUpkeep with default parameters
        try fumVault.checkUpkeep("") returns (bool upkeepNeeded, bytes memory performData) {
            console.log("Upkeep needed:", upkeepNeeded);
            
            if (upkeepNeeded) {
                uint256[] memory vaultIds = abi.decode(performData, (uint256[]));
                console.log("Vaults ready to unlock:", vaultIds.length);
                for (uint256 i = 0; i < vaultIds.length && i < 5; i++) {
                    console.log("  Vault ID:", vaultIds[i]);
                }
            } else {
                console.log("No vaults ready for unlock");
            }
        } catch Error(string memory reason) {
            console.log("[ERROR] checkUpkeep failed:", reason);
        } catch {
            console.log("[ERROR] checkUpkeep failed with unknown error");
        }
        
        // Test with custom parameters
        bytes memory checkData = abi.encode(1, 100, 10); // Check vaults 1-100, max 10
        try fumVault.checkUpkeep(checkData) returns (bool upkeepNeeded, bytes memory performData) {
            console.log("Custom checkUpkeep - Upkeep needed:", upkeepNeeded);
            if (upkeepNeeded) {
                uint256[] memory vaultIds = abi.decode(performData, (uint256[]));
                console.log("Custom checkUpkeep - Vaults ready:", vaultIds.length);
            }
        } catch {
            console.log("[ERROR] Custom checkUpkeep failed");
        }
    }
    
    function testConfiguration(FUMVault fumVault) internal view {
        // Test basic configuration
        try fumVault.owner() returns (address owner) {
            console.log("Contract owner:", owner);
        } catch {
            console.log("[ERROR] Could not get owner");
        }
        
        try fumVault.nextVaultId() returns (uint256 nextId) {
            console.log("Next vault ID:", nextId);
            console.log("Total vaults created:", nextId - 1);
        } catch {
            console.log("[ERROR] Could not get next vault ID");
        }
        
        try fumVault.checkInterval() returns (uint256 interval) {
            console.log("Check interval:", interval, "seconds");
        } catch {
            console.log("[ERROR] Could not get check interval");
        }
        
        try fumVault.lastCheckTimestamp() returns (uint256 lastCheck) {
            console.log("Last check timestamp:", lastCheck);
            if (lastCheck > 0) {
                console.log("Time since last check:", block.timestamp - lastCheck, "seconds");
            } else {
                console.log("No checks performed yet");
            }
        } catch {
            console.log("[ERROR] Could not get last check timestamp");
        }
        
        // Test contract stats
        try fumVault.getContractStats() returns (uint256 totalVaults, uint256 contractBalance) {
            console.log("Contract stats:");
            console.log("  Total vaults:", totalVaults);
            console.log("  ETH balance:", contractBalance);
        } catch {
            console.log("[ERROR] Could not get contract stats");
        }
        
        // Test supported tokens
        console.log("Token support:");
        console.log("  ETH supported:", fumVault.supportedTokens(address(0)));
        
        // Test constants
        console.log("Contract constants:");
        console.log("  Emergency penalty:", fumVault.EMERGENCY_PENALTY(), "basis points");
        console.log("  Penalty claim delay:", fumVault.PENALTY_CLAIM_DELAY(), "seconds");
        console.log("  Basis points:", fumVault.BASIS_POINTS());
    }
}

/// @title Create Test Vault Script
/// @notice Script to create a test vault on real network
contract CreateTestVault is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address fumVaultAddress = vm.envAddress("FUM_VAULT_ADDRESS");
        
        console.log("Creating test vault...");
        console.log("FUMVault address:", fumVaultAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        FUMVault fumVault = FUMVault(payable(fumVaultAddress));
        
        // Create a time-based vault (unlock in 1 hour)
        uint256 unlockTime = block.timestamp + 1 hours;
        uint256 vaultAmount = 0.01 ether; // Small amount for testing
        
        uint256 vaultId = fumVault.createTimeVault{value: vaultAmount}(
            address(0),  // ETH
            vaultAmount,
            unlockTime
        );
        
        console.log("Test vault created!");
        console.log("Vault ID:", vaultId);
        console.log("Amount:", vaultAmount);
        console.log("Unlock time:", unlockTime);
        console.log("Current time:", block.timestamp);
        console.log("Time until unlock:", unlockTime - block.timestamp, "seconds");
        
        vm.stopBroadcast();
    }
}

/// @title Create Price Vault Script
/// @notice Script to create a price-based test vault
contract CreatePriceVault is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address fumVaultAddress = vm.envAddress("FUM_VAULT_ADDRESS");
        
        console.log("Creating price-based test vault...");
        
        vm.startBroadcast(deployerPrivateKey);
        
        FUMVault fumVault = FUMVault(payable(fumVaultAddress));
        
        // Get current ETH price
        uint256 currentPrice = fumVault.getCurrentPrice(address(0));
        console.log("Current ETH price:", currentPrice);
        
        // Set target price 5% higher than current
        uint256 targetPrice = currentPrice * 105 / 100;
        uint256 vaultAmount = 0.01 ether;
        
        uint256 vaultId = fumVault.createPriceVault{value: vaultAmount}(
            address(0),  // ETH
            vaultAmount,
            targetPrice
        );
        
        console.log("Price vault created!");
        console.log("Vault ID:", vaultId);
        console.log("Amount:", vaultAmount);
        console.log("Current price:", currentPrice);
        console.log("Target price:", targetPrice);
        console.log("Price increase needed:", ((targetPrice - currentPrice) * 100) / currentPrice, "%");
        
        vm.stopBroadcast();
    }
}
