// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FUMVault.sol";

/// @title Create Test Vaults
contract CreateVaults is Script {

    function run() external {
        address fumVaultAddress = vm.envAddress("FUM_VAULT_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("=== Creating Test Vaults ===");
        console.log("Contract Address:", fumVaultAddress);

        FUMVault fumVault = FUMVault(payable(fumVaultAddress));

        vm.startBroadcast(deployerPrivateKey);

        // Set higher gas price for faster confirmation
        vm.txGasPrice(30000000000); // 30 gwei

        // 1. Create Time Vault (unlock in 1 minute)
        console.log("\n--- Creating Time Vault ---");
        uint256 timeUnlock = block.timestamp + 1 minutes;
        uint256 timeAmount = 0.1 ether;

        uint256 timeVaultId = fumVault.createTimeVault{value: timeAmount}(
            address(0), // ETH
            timeAmount,
            timeUnlock
        );

        console.log("Time Vault Created:");
        console.log("   Vault ID:", timeVaultId);
        console.log("   Amount:", timeAmount);
        console.log("   Unlock Time:", timeUnlock);
        console.log("   Time Until Unlock:", timeUnlock - block.timestamp, "seconds");

        // 2. Create Price Vault (unlock when ETH hits +1% current price)
        console.log("\n--- Creating Price Vault ---");
        uint256 currentEthPrice = fumVault.getCurrentPrice(address(0));
        uint256 targetPrice = currentEthPrice * 101 / 100; // 1% higher
        uint256 priceAmount = 0.1 ether;

        uint256 priceVaultId = fumVault.createPriceVault{value: priceAmount}(
            address(0), // ETH
            priceAmount,
            targetPrice
        );

        console.log("Price Vault Created:");
        console.log("   Vault ID:", priceVaultId);
        console.log("   Amount:", priceAmount);
        console.log("   Current ETH Price: $", currentEthPrice / 1e8);
        console.log("   Target Price: $", targetPrice / 1e8);
        console.log("   Price Increase Needed:", ((targetPrice - currentEthPrice) * 100) / currentEthPrice, "%");

        // 3. Create Combined Vault (unlock when ETH hits +1% OR after 1 minute)
        console.log("\n--- Creating Time OR Price Vault ---");
        uint256 combinedUnlock = block.timestamp + 1 minutes;
        uint256 combinedTargetPrice = currentEthPrice * 101 / 100; // 1% higher
        uint256 combinedAmount = 0.1 ether;

        uint256 combinedVaultId = fumVault.createTimeOrPriceVault{value: combinedAmount}(
            address(0), // ETH
            combinedAmount,
            combinedUnlock,
            combinedTargetPrice
        );

        console.log("Time OR Price Vault Created:");
        console.log("   Vault ID:", combinedVaultId);
        console.log("   Amount:", combinedAmount);
        console.log("   Unlock Time:", combinedUnlock);
        console.log("   Target Price: $", combinedTargetPrice / 1e8);
        console.log("   Conditions: Time (1 minute) OR Price (+1%)");

        vm.stopBroadcast();

        console.log("\n=== Vault Creation Complete ===");
        console.log("Created 3 test vaults with different conditions");
        console.log("Use CheckVaults script to monitor their status");
    }
}

/// @title Check Vault Status
contract CheckVaults is Script {

    function run() external view {
        address fumVaultAddress = vm.envAddress("FUM_VAULT_ADDRESS");

        console.log("=== Checking Vault Status ===");
        console.log("Contract Address:", fumVaultAddress);
        console.log("Current Time:", block.timestamp);

        FUMVault fumVault = FUMVault(payable(fumVaultAddress));

        // Get contract stats
        (uint256 totalVaults, uint256 contractBalance) = fumVault.getContractStats();
        console.log("\n--- Contract Stats ---");
        console.log("Total Vaults:", totalVaults);
        console.log("Contract Balance:", contractBalance);

        // Check each vault
        for (uint256 i = 1; i <= totalVaults; i++) {
            console.log("\n--- Vault", i, "---");

            try fumVault.getVault(i) returns (FUMVault.Vault memory vault) {
                console.log("Owner:", vault.owner);
                console.log("Token:", vault.token == address(0) ? "ETH" : "Token");
                console.log("Amount:", vault.amount);
                console.log("Status:", uint256(vault.status));
                console.log("Condition Type:", uint256(vault.conditionType));

                if (vault.unlockTime > 0) {
                    console.log("Unlock Time:", vault.unlockTime);
                    if (block.timestamp >= vault.unlockTime) {
                        console.log("Time condition: MET");
                    } else {
                        console.log("Time condition: NOT MET (", vault.unlockTime - block.timestamp, "seconds remaining)");
                    }
                }

                if (vault.targetPrice > 0) {
                    console.log("Target Price: $", vault.targetPrice / 1e8);
                    try fumVault.getCurrentPrice(vault.token) returns (uint256 currentPrice) {
                        console.log("Current Price: $", currentPrice / 1e8);
                        if (currentPrice >= vault.targetPrice) {
                            console.log("Price condition: MET");
                        } else {
                            console.log("Price condition: NOT MET");
                        }
                    } catch {
                        console.log("Price condition: ERROR");
                    }
                }

                // Check overall conditions
                bool conditionsMet = fumVault.checkConditions(i);
                console.log("Overall Conditions:", conditionsMet ? "MET" : "NOT MET");

            } catch {
                console.log("Failed to get vault info");
            }
        }

        // Check automation
        console.log("\n--- Automation Status ---");
        try fumVault.checkUpkeep("") returns (bool upkeepNeeded, bytes memory performData) {
            console.log("Upkeep Needed:", upkeepNeeded);
            if (upkeepNeeded) {
                uint256[] memory readyVaults = abi.decode(performData, (uint256[]));
                console.log("Vaults Ready to Unlock:", readyVaults.length);
                for (uint256 i = 0; i < readyVaults.length; i++) {
                    console.log("   Vault ID:", readyVaults[i]);
                }
            } else {
                console.log("No vaults ready to unlock");
            }
        } catch {
            console.log("Automation check failed");
        }

        console.log("Check Interval:", fumVault.checkInterval(), "seconds");
        console.log("Last Check:", fumVault.lastCheckTimestamp());
    }
}

/// @title Withdraw from Vault
contract WithdrawVault is Script {

    function run() external {
        address fumVaultAddress = vm.envAddress("FUM_VAULT_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 vaultId = vm.envUint("VAULT_ID"); // Set this: export VAULT_ID=1

        console.log("=== Withdrawing from Vault ===");
        console.log("Contract Address:", fumVaultAddress);
        console.log("Vault ID:", vaultId);

        FUMVault fumVault = FUMVault(payable(fumVaultAddress));

        // Check vault status first
        FUMVault.Vault memory vault = fumVault.getVault(vaultId);
        console.log("Vault Owner:", vault.owner);
        console.log("Vault Amount:", vault.amount);
        console.log("Vault Status:", uint256(vault.status));

        bool conditionsMet = fumVault.checkConditions(vaultId);
        console.log("Conditions Met:", conditionsMet);

        if (!conditionsMet) {
            console.log("Cannot withdraw: conditions not met");
            return;
        }

        vm.startBroadcast(deployerPrivateKey);

        uint256 balanceBefore = msg.sender.balance;

        try fumVault.withdrawVault(vaultId) {
            uint256 balanceAfter = msg.sender.balance;
            uint256 received = balanceAfter - balanceBefore;

            console.log("Withdrawal successful!");
            console.log("Amount received:", received);
            console.log("New balance:", balanceAfter);
        } catch Error(string memory reason) {
            console.log("Withdrawal failed:", reason);
        } catch {
            console.log("Withdrawal failed with unknown error");
        }

        vm.stopBroadcast();
    }
}

/// @title Emergency Withdrawal
contract EmergencyWithdraw is Script {

    function run() external {
        address fumVaultAddress = vm.envAddress("FUM_VAULT_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 vaultId = vm.envUint("VAULT_ID"); // Set this: export VAULT_ID=1

        console.log("=== Emergency Withdrawal ===");
        console.log("Contract Address:", fumVaultAddress);
        console.log("Vault ID:", vaultId);
        console.log("WARNING: 10% penalty will be applied");

        FUMVault fumVault = FUMVault(payable(fumVaultAddress));

        // Check vault info
        FUMVault.Vault memory vault = fumVault.getVault(vaultId);
        console.log("Vault Amount:", vault.amount);

        uint256 penalty = vault.amount * fumVault.EMERGENCY_PENALTY() / fumVault.BASIS_POINTS();
        uint256 withdrawAmount = vault.amount - penalty;

        console.log("Amount to receive (90%):", withdrawAmount);
        console.log("Penalty (10%):", penalty);
        console.log("Penalty can be claimed after 3 months");

        vm.startBroadcast(deployerPrivateKey);

        uint256 balanceBefore = msg.sender.balance;

        try fumVault.executeEmergencyWithdrawal(vaultId) {
            uint256 balanceAfter = msg.sender.balance;
            uint256 received = balanceAfter - balanceBefore;

            console.log("Emergency withdrawal successful!");
            console.log("Amount received:", received);
            console.log("Penalty stored for 3 months:", penalty);

            // Check penalty info
            FUMVault.EmergencyPenalty memory penaltyInfo = fumVault.getEmergencyPenalty(msg.sender);
            console.log("Total penalty amount:", penaltyInfo.amount);
            console.log("Penalty time:", penaltyInfo.penaltyTime);
            console.log("Can claim after:", penaltyInfo.penaltyTime + fumVault.PENALTY_CLAIM_DELAY());

        } catch Error(string memory reason) {
            console.log("Emergency withdrawal failed:", reason);
        } catch {
            console.log("Emergency withdrawal failed with unknown error");
        }

        vm.stopBroadcast();
    }
}
