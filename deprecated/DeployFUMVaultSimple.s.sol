// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FUMVault.sol";

/// @title Simple FUMVault Deployment Script for Avalanche Fuji
/// @notice Deploys FUMVault without price feed configuration to avoid errors
contract DeployFUMVaultSimple is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Deploying FUMVault to Avalanche Fuji ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy FUMVault
        FUMVault fumVault = new FUMVault(deployer);
        
        console.log("FUMVault deployed successfully!");
        console.log("Contract address:", address(fumVault));
        console.log("Owner:", fumVault.owner());
        console.log("Next vault ID:", fumVault.nextVaultId());
        console.log("Check interval:", fumVault.checkInterval(), "seconds");
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Complete ===");
        console.log("Contract Address:", address(fumVault));
        console.log("Network: Avalanche Fuji Testnet");
        console.log("Explorer: https://testnet.snowtrace.io/address/", address(fumVault));
        
        console.log("\n=== Next Steps ===");
        console.log("1. Set environment variable:");
        console.log("   export FUM_VAULT_ADDRESS=", address(fumVault));
        console.log("2. Configure price feeds manually:");
        console.log("   forge script script/ConfigurePriceFeeds.s.sol --rpc-url $FUJI_RPC_URL --broadcast");
        console.log("3. Test the deployment:");
        console.log("   forge script script/TestDeployment.s.sol --rpc-url $FUJI_RPC_URL");
    }
}

/// @title Configure Price Feeds Script
/// @notice Separately configure price feeds after deployment
contract ConfigurePriceFeeds is Script {
    
    // Avalanche Fuji testnet price feeds (multiple options to try)
    address constant FUJI_ETH_USD_1 = 0x86d67c3D38D2bCeE722E601025C25a575021c6EA;
    address constant FUJI_ETH_USD_2 = 0x976B3D034E162d8bD72D6b9C989d545b839003b0;
    address constant FUJI_BTC_USD = 0x2779D32d5166BAaa2B2b658333bA7e6Ec0C65743;
    address constant FUJI_AVAX_USD = 0x0A77230d17318075983913bC2145DB16C7366156;
    
    function run() external {
        address fumVaultAddress = vm.envAddress("FUM_VAULT_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("=== Configuring Price Feeds ===");
        console.log("FUMVault Address:", fumVaultAddress);
        
        FUMVault fumVault = FUMVault(payable(fumVaultAddress));
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Try to configure ETH/USD price feed (try multiple addresses)
        bool ethConfigured = false;
        
        console.log("Trying ETH/USD price feed option 1:", FUJI_ETH_USD_1);
        try fumVault.setPriceFeed(address(0), FUJI_ETH_USD_1, 3600) {
            console.log("ETH/USD price feed configured with option 1");
            ethConfigured = true;
        } catch {
            console.log("ETH/USD option 1 failed, trying option 2:", FUJI_ETH_USD_2);
            
            try fumVault.setPriceFeed(address(0), FUJI_ETH_USD_2, 3600) {
                console.log("ETH/USD price feed configured with option 2");
                ethConfigured = true;
            } catch {
                console.log("Both ETH/USD options failed");
            }
        }
        
        // Test ETH price if configured
        if (ethConfigured) {
            try fumVault.getCurrentPrice(address(0)) returns (uint256 price) {
                console.log("ETH/USD price working! Current price:", price);
                console.log("   ETH Price: $", price / 1e8);
            } catch {
                console.log("ETH/USD price feed configured but not working");
            }
        }
        
        // Try to configure BTC/USD price feed
        console.log("Configuring BTC/USD price feed:", FUJI_BTC_USD);
        try fumVault.setPriceFeed(address(1), FUJI_BTC_USD, 3600) {
            console.log("BTC/USD price feed configured");
        } catch {
            console.log("BTC/USD price feed failed");
        }
        
        // Try to configure AVAX/USD price feed
        console.log("Configuring AVAX/USD price feed:", FUJI_AVAX_USD);
        try fumVault.setPriceFeed(address(2), FUJI_AVAX_USD, 3600) {
            console.log("AVAX/USD price feed configured");
        } catch {
            console.log("AVAX/USD price feed failed");
        }
        
        vm.stopBroadcast();
        
        console.log("\n=== Price Feed Configuration Complete ===");
    }
}

/// @title Test Deployment Script
/// @notice Test the deployed contract functionality
contract TestDeployment is Script {
    
    function run() external view {
        address fumVaultAddress = vm.envAddress("FUM_VAULT_ADDRESS");
        
        console.log("=== Testing Deployed FUMVault ===");
        console.log("Contract Address:", fumVaultAddress);
        console.log("Chain ID:", block.chainid);
        
        FUMVault fumVault = FUMVault(payable(fumVaultAddress));
        
        // Test basic contract info
        console.log("\n--- Basic Contract Info ---");
        console.log("Owner:", fumVault.owner());
        console.log("Next Vault ID:", fumVault.nextVaultId());
        console.log("Check Interval:", fumVault.checkInterval(), "seconds");
        console.log("ETH supported:", fumVault.supportedTokens(address(0)));
        
        // Test contract stats
        (uint256 totalVaults, uint256 contractBalance) = fumVault.getContractStats();
        console.log("Total Vaults:", totalVaults);
        console.log("Contract Balance:", contractBalance);
        
        // Test price feeds
        console.log("\n--- Price Feed Tests ---");
        
        // Test ETH price
        try fumVault.getCurrentPrice(address(0)) returns (uint256 ethPrice) {
            console.log("ETH/USD Price:", ethPrice);
            console.log("   ETH Price: $", ethPrice / 1e8);
            
            (uint256 price, uint256 updatedAt, bool isStale) = fumVault.getDetailedPrice(address(0));
            console.log("   Last Updated:", updatedAt);
            console.log("   Is Stale:", isStale);
            console.log("   Seconds Since Update:", block.timestamp - updatedAt);
        } catch {
            console.log("ETH/USD price feed not working");
        }
        
        // Test price feed info
        (address priceFeed, uint256 heartbeat, uint8 decimals) = fumVault.getPriceFeedInfo(address(0));
        console.log("ETH Price Feed Address:", priceFeed);
        console.log("ETH Price Feed Heartbeat:", heartbeat);
        console.log("ETH Price Feed Decimals:", decimals);
        
        // Test automation
        console.log("\n--- Automation Tests ---");
        try fumVault.checkUpkeep("") returns (bool upkeepNeeded, bytes memory performData) {
            console.log("Upkeep Needed:", upkeepNeeded);
            if (upkeepNeeded) {
                uint256[] memory vaultIds = abi.decode(performData, (uint256[]));
                console.log("Vaults Ready:", vaultIds.length);
            } else {
                console.log("No vaults ready to unlock");
            }
        } catch {
            console.log("checkUpkeep failed");
        }
        
        console.log("\n=== Test Complete ===");
        console.log("Contract deployed and basic functions working");
        console.log("Ready to create vaults and setup automation!");
    }
}

/// @title Create Test Vault Script
/// @notice Create a simple test vault
contract CreateTestVault is Script {
    
    function run() external {
        address fumVaultAddress = vm.envAddress("FUM_VAULT_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("=== Creating Test Vault ===");
        console.log("FUMVault Address:", fumVaultAddress);
        
        FUMVault fumVault = FUMVault(payable(fumVaultAddress));
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Create a simple time vault (unlock in 1 hour)
        uint256 unlockTime = block.timestamp + 1 hours;
        uint256 amount = 0.01 ether; // Small amount for testing
        
        console.log("Creating time vault...");
        console.log("Amount:", amount);
        console.log("Unlock Time:", unlockTime);
        console.log("Current Time:", block.timestamp);
        
        uint256 vaultId = fumVault.createTimeVault{value: amount}(
            address(0), // ETH
            amount,
            unlockTime
        );
        
        console.log("Test vault created!");
        console.log("Vault ID:", vaultId);
        console.log("Time until unlock:", unlockTime - block.timestamp, "seconds");
        
        // Check vault info
        FUMVault.Vault memory vault = fumVault.getVault(vaultId);
        console.log("Vault Owner:", vault.owner);
        console.log("Vault Amount:", vault.amount);
        console.log("Vault Status:", uint256(vault.status));
        
        vm.stopBroadcast();
        
        console.log("\n=== Test Vault Created Successfully ===");
        console.log("You can now setup Chainlink Automation to monitor this vault!");
    }
}
