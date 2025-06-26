// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FUMVault.sol";

/// @title ViewUnlockedVaults - Script untuk melihat vault yang sudah unlocked
/// @notice Script ini akan scan semua vault dan tampilkan yang statusnya UNLOCKED
contract ViewUnlockedVaults is Script {

    // Contract address di Avalanche Fuji
    address constant FUM_VAULT_ADDRESS = 0x5274A2153cF842E3bD1D4996E01d567750d0e739;

    function run() external view {
        console.log("=== Scanning for Unlocked Vaults ===");
        console.log("Contract Address:", FUM_VAULT_ADDRESS);
        console.log("");

        FUMVault fumVault = FUMVault(payable(FUM_VAULT_ADDRESS));

        // Get total number of vaults
        (uint256 totalVaults, uint256 contractBalance) = fumVault.getContractStats();
        console.log("Total Vaults Created:", totalVaults);
        console.log("Contract ETH Balance:", contractBalance / 1e18, "ETH");
        console.log("");

        uint256 unlockedCount = 0;
        uint256 activeCount = 0;
        uint256 withdrawnCount = 0;

        // Scan through all vaults
        for (uint256 vaultId = 1; vaultId <= totalVaults; vaultId++) {
            try fumVault.getVault(vaultId) returns (FUMVault.Vault memory vault) {
                if (vault.owner == address(0)) continue; // Skip empty vaults

                string memory statusStr = getStatusString(vault.status);
                string memory conditionStr = getConditionString(vault.conditionType);

                // Count by status
                if (vault.status == FUMVault.VaultStatus.UNLOCKED) {
                    unlockedCount++;
                } else if (vault.status == FUMVault.VaultStatus.ACTIVE) {
                    activeCount++;
                } else if (vault.status == FUMVault.VaultStatus.WITHDRAWN) {
                    withdrawnCount++;
                }

                // Display vault info
                console.log("--- Vault ID:", vaultId, "---");
                console.log("Owner:", vault.owner);
                console.log("Token:", vault.token == address(0) ? "ETH" : addressToString(vault.token));
                console.log("Amount:", vault.amount / 1e18, "tokens");
                console.log("Status:", statusStr);
                console.log("Condition Type:", conditionStr);

                if (vault.unlockTime > 0) {
                    if (block.timestamp >= vault.unlockTime) {
                        console.log("Time Condition: MET (unlocked at", vault.unlockTime, ")");
                    } else {
                        console.log("Time Condition: NOT MET (unlocks at", vault.unlockTime, ")");
                        console.log("Time remaining:", (vault.unlockTime - block.timestamp) / 60, "minutes");
                    }
                }

                if (vault.targetPrice > 0) {
                    try fumVault.getCurrentPrice(vault.token) returns (uint256 currentPrice) {
                        console.log("Target Price:", vault.targetPrice / 1e8, "USD");
                        console.log("Current Price:", currentPrice / 1e8, "USD");
                        if (currentPrice >= vault.targetPrice) {
                            console.log("Price Condition: MET");
                        } else {
                            console.log("Price Condition: NOT MET");
                        }
                    } catch {
                        console.log("Price Condition: ERROR (price feed issue)");
                    }
                }

                // Check if conditions are met
                try fumVault.checkConditions(vaultId) returns (bool conditionsMet) {
                    console.log("Overall Conditions Met:", conditionsMet ? "YES" : "NO");
                } catch {
                    console.log("Overall Conditions Met: ERROR");
                }

                console.log("Created At:", vault.createdAt);
                console.log("");

            } catch {
                console.log("Error reading vault", vaultId);
            }
        }

        // Summary
        console.log("=== SUMMARY ===");
        console.log("Total Vaults:", totalVaults);
        console.log("Active Vaults:", activeCount);
        console.log("Unlocked Vaults:", unlockedCount);
        console.log("Withdrawn Vaults:", withdrawnCount);
        console.log("");

        if (unlockedCount > 0) {
            console.log("Found", unlockedCount, "unlocked vault(s) ready for withdrawal!");
            console.log("Use ClaimUnlockedVaults.s.sol script to claim them.");
        } else {
            console.log("No unlocked vaults found. Check back later or create test vaults.");
        }
    }

    function getStatusString(FUMVault.VaultStatus status) internal pure returns (string memory) {
        if (status == FUMVault.VaultStatus.ACTIVE) return "ACTIVE";
        if (status == FUMVault.VaultStatus.UNLOCKED) return "UNLOCKED";
        if (status == FUMVault.VaultStatus.WITHDRAWN) return "WITHDRAWN";
        if (status == FUMVault.VaultStatus.EMERGENCY) return "EMERGENCY";
        return "UNKNOWN";
    }

    function getConditionString(FUMVault.ConditionType conditionType) internal pure returns (string memory) {
        if (conditionType == FUMVault.ConditionType.TIME_ONLY) return "TIME_ONLY";
        if (conditionType == FUMVault.ConditionType.PRICE_ONLY) return "PRICE_ONLY";
        if (conditionType == FUMVault.ConditionType.TIME_OR_PRICE) return "TIME_OR_PRICE";
        if (conditionType == FUMVault.ConditionType.TIME_AND_PRICE) return "TIME_AND_PRICE";
        return "UNKNOWN";
    }

    function addressToString(address addr) internal pure returns (string memory) {
        bytes memory data = abi.encodePacked(addr);
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint i = 0; i < data.length; i++) {
            str[2+i*2] = alphabet[uint(uint8(data[i] >> 4))];
            str[3+i*2] = alphabet[uint(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }
}

/// @title ViewUserVaults - Script untuk melihat vault milik user tertentu
contract ViewUserVaults is Script {

    address constant FUM_VAULT_ADDRESS = 0x5274A2153cF842E3bD1D4996E01d567750d0e739;

    function run() external view {
        // Get user address from environment or use msg.sender
        address userAddress = vm.envOr("USER_ADDRESS", msg.sender);

        console.log("=== Viewing Vaults for User ===");
        console.log("User Address:", userAddress);
        console.log("Contract Address:", FUM_VAULT_ADDRESS);
        console.log("");

        FUMVault fumVault = FUMVault(payable(FUM_VAULT_ADDRESS));

        // Get user's vault IDs
        uint256[] memory userVaultIds = fumVault.getOwnerVaults(userAddress);

        if (userVaultIds.length == 0) {
            console.log("No vaults found for this user.");
            return;
        }

        console.log("Found", userVaultIds.length, "vault(s) for this user:");
        console.log("");

        uint256 unlockedCount = 0;
        uint256 totalValue = 0;

        for (uint256 i = 0; i < userVaultIds.length; i++) {
            uint256 vaultId = userVaultIds[i];

            try fumVault.getVault(vaultId) returns (FUMVault.Vault memory vault) {
                string memory statusStr = getStatusString(vault.status);

                console.log("--- Vault ID:", vaultId, "---");
                console.log("Token:", vault.token == address(0) ? "ETH" : addressToString(vault.token));
                console.log("Amount:", vault.amount / 1e18, "tokens");
                console.log("Status:", statusStr);

                if (vault.status == FUMVault.VaultStatus.UNLOCKED) {
                    unlockedCount++;
                    console.log("READY FOR WITHDRAWAL!");
                }

                if (vault.status == FUMVault.VaultStatus.ACTIVE || vault.status == FUMVault.VaultStatus.UNLOCKED) {
                    totalValue += vault.amount;
                }

                console.log("");
            } catch {
                console.log("Error reading vault", vaultId);
            }
        }

        console.log("=== USER SUMMARY ===");
        console.log("Total Vaults:", userVaultIds.length);
        console.log("Unlocked Vaults:", unlockedCount);
        console.log("Total Locked Value:", totalValue / 1e18, "ETH");

        if (unlockedCount > 0) {
            console.log("");
            console.log("You have", unlockedCount, "vault(s) ready for withdrawal!");
            console.log("Run: forge script script/ClaimUnlockedVaults.s.sol --rpc-url $FUJI_RPC_URL --broadcast");
        }
    }

    function getStatusString(FUMVault.VaultStatus status) internal pure returns (string memory) {
        if (status == FUMVault.VaultStatus.ACTIVE) return "ACTIVE";
        if (status == FUMVault.VaultStatus.UNLOCKED) return "UNLOCKED";
        if (status == FUMVault.VaultStatus.WITHDRAWN) return "WITHDRAWN";
        if (status == FUMVault.VaultStatus.EMERGENCY) return "EMERGENCY";
        return "UNKNOWN";
    }

    function addressToString(address addr) internal pure returns (string memory) {
        bytes memory data = abi.encodePacked(addr);
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint i = 0; i < data.length; i++) {
            str[2+i*2] = alphabet[uint(uint8(data[i] >> 4))];
            str[3+i*2] = alphabet[uint(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }
}
