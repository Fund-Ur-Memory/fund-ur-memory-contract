// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FUMVault.sol";

/// @title MonitorAutomation - Script untuk monitor status Chainlink Automation
/// @notice Script ini akan check status automation dan vault yang ready untuk unlock
contract MonitorAutomation is Script {

    address constant FUM_VAULT_ADDRESS = 0x5274A2153cF842E3bD1D4996E01d567750d0e739;

    function run() external view {
        console.log("=== F.U.M Automation Monitor ===");
        console.log("Contract Address:", FUM_VAULT_ADDRESS);
        console.log("Timestamp:", block.timestamp);
        console.log("");

        FUMVault fumVault = FUMVault(payable(FUM_VAULT_ADDRESS));

        // Get contract stats
        (uint256 totalVaults, uint256 contractBalance) = fumVault.getContractStats();
        console.log("--- Contract Status ---");
        console.log("Total Vaults:", totalVaults);
        console.log("Contract Balance:", contractBalance / 1e18, "ETH");

        // Get automation settings
        uint256 checkInterval = fumVault.checkInterval();
        uint256 lastCheckTimestamp = fumVault.lastCheckTimestamp();

        console.log("Check Interval:", checkInterval, "seconds");
        console.log("Last Check:", lastCheckTimestamp);

        if (lastCheckTimestamp > 0) {
            uint256 timeSinceLastCheck = block.timestamp - lastCheckTimestamp;
            console.log("Time Since Last Check:", timeSinceLastCheck, "seconds");

            if (timeSinceLastCheck >= checkInterval) {
                console.log("Ready for next automation check");
            } else {
                console.log("Next check in:", checkInterval - timeSinceLastCheck, "seconds");
            }
        } else {
            console.log("No automation checks performed yet");
        }

        console.log("");

        // Check if upkeep is needed
        console.log("--- Automation Status ---");
        bool upkeepNeeded = false;
        try fumVault.checkUpkeep("") returns (bool _upkeepNeeded, bytes memory performData) {
            upkeepNeeded = _upkeepNeeded;
            if (upkeepNeeded) {
                uint256[] memory readyVaultIds = abi.decode(performData, (uint256[]));
                console.log("UPKEEP NEEDED!");
                console.log("Ready Vaults:", readyVaultIds.length);

                for (uint256 i = 0; i < readyVaultIds.length; i++) {
                    console.log("  - Vault ID:", readyVaultIds[i]);
                }

                console.log("");
                console.log("Chainlink will automatically call performUpkeep() soon");
            } else {
                console.log("No upkeep needed - all vaults are properly managed");
            }
        } catch {
            console.log("Error checking upkeep status");
        }

        console.log("");

        // Scan active vaults
        console.log("--- Active Vaults Analysis ---");
        uint256 activeCount = 0;
        uint256 readyCount = 0;
        uint256 timeBasedReady = 0;
        uint256 priceBasedReady = 0;

        for (uint256 vaultId = 1; vaultId <= totalVaults; vaultId++) {
            try fumVault.getVault(vaultId) returns (FUMVault.Vault memory vault) {
                if (vault.owner == address(0)) continue;

                if (vault.status == FUMVault.VaultStatus.ACTIVE) {
                    activeCount++;

                    // Check conditions
                    try fumVault.checkConditions(vaultId) returns (bool conditionsMet) {
                        if (conditionsMet) {
                            readyCount++;

                            // Analyze what made it ready
                            bool timeReady = vault.unlockTime > 0 && block.timestamp >= vault.unlockTime;
                            bool priceReady = false;

                            if (vault.targetPrice > 0) {
                                try fumVault.getCurrentPrice(vault.token) returns (uint256 currentPrice) {
                                    priceReady = currentPrice >= vault.targetPrice;
                                } catch {
                                    // Price feed error
                                }
                            }

                            if (timeReady) timeBasedReady++;
                            if (priceReady) priceBasedReady++;
                        }
                    } catch {
                        // Error checking conditions
                    }
                }
            } catch {
                // Error reading vault
            }
        }

        console.log("Active Vaults:", activeCount);
        console.log("Ready for Unlock:", readyCount);
        console.log("  - Time-based ready:", timeBasedReady);
        console.log("  - Price-based ready:", priceBasedReady);

        if (readyCount > 0) {
            console.log("");
            console.log("Expected Actions:");
            console.log("  1. Chainlink will detect these vaults");
            console.log("  2. performUpkeep() will be called automatically");
            console.log("  3. Vaults will be unlocked");
            console.log("  4. Users can withdraw their funds");
        }

        console.log("");

        // Price feed status
        console.log("--- Price Feed Status ---");
        address[] memory tokens = new address[](3);
        tokens[0] = address(0); // ETH
        tokens[1] = 0x0000000000000000000000000000000000000001; // Placeholder for BTC
        tokens[2] = 0x0000000000000000000000000000000000000002; // Placeholder for AVAX

        string[] memory tokenNames = new string[](3);
        tokenNames[0] = "ETH";
        tokenNames[1] = "BTC";
        tokenNames[2] = "AVAX";

        for (uint256 i = 0; i < tokens.length; i++) {
            try fumVault.getDetailedPrice(tokens[i]) returns (
                uint256 price,
                uint256 updatedAt,
                bool isStale
            ) {
                console.log(tokenNames[i], "Price:", price / 1e8, "USD");
                console.log("  Last Updated:", updatedAt);
                console.log("  Is Stale:", isStale ? "YES" : "NO");

                if (updatedAt > 0) {
                    uint256 ageSeconds = block.timestamp - updatedAt;
                    console.log("  Age:", ageSeconds / 60, "minutes");
                }
                console.log("");
            } catch {
                console.log(tokenNames[i], "Price: ERROR (not configured or feed issue)");
                console.log("");
            }
        }

        // Final recommendations
        console.log("--- Recommendations ---");
        if (readyCount > 0 && !upkeepNeeded) {
            console.log("Vaults are ready but upkeep not triggered - check automation setup");
        } else if (activeCount == 0) {
            console.log("No active vaults - create some test vaults to see automation in action");
        } else if (readyCount == 0) {
            console.log("All active vaults are properly locked - automation working correctly");
        } else {
            console.log("Automation is working correctly");
        }
    }
}

/// @title TestAutomationFlow - Script untuk test complete automation flow
contract TestAutomationFlow is Script {

    address constant FUM_VAULT_ADDRESS = 0x5274A2153cF842E3bD1D4996E01d567750d0e739;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("=== Testing Complete Automation Flow ===");
        console.log("This will create test vaults and monitor automation");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        FUMVault fumVault = FUMVault(payable(FUM_VAULT_ADDRESS));

        // Create a time vault that unlocks in 1 minute (for quick testing)
        uint256 unlockTime = block.timestamp + 60; // 1 minute

        console.log("Creating test time vault (unlocks in 1 minute)...");
        try fumVault.createTimeVault{value: 0.01 ether}(
            address(0), // ETH
            0.01 ether,
            unlockTime
        ) returns (uint256 vaultId) {
            console.log("Created vault ID:", vaultId);
            console.log("Unlock time:", unlockTime);
            console.log("Current time:", block.timestamp);
            console.log("");

            // Check initial status
            console.log("--- Initial Status ---");
            (bool upkeepNeeded,) = fumVault.checkUpkeep("");
            console.log("Upkeep needed:", upkeepNeeded ? "YES" : "NO");

            bool conditionsMet = fumVault.checkConditions(vaultId);
            console.log("Conditions met:", conditionsMet ? "YES" : "NO");

            console.log("");
            console.log("Wait 1 minute, then run MonitorAutomation to see automation trigger");
            console.log("Command: forge script script/MonitorAutomation.s.sol:MonitorAutomation --rpc-url $FUJI_RPC_URL");

        } catch Error(string memory reason) {
            console.log("Failed to create test vault - Reason:", reason);
        } catch {
            console.log("Failed to create test vault - Unknown error");
        }

        vm.stopBroadcast();
    }
}
