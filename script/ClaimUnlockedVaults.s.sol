// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FUMVault.sol";

/// @title ClaimUnlockedVaults - Script untuk claim vault yang sudah unlocked
/// @notice Script ini akan otomatis claim semua vault yang sudah unlocked milik user
contract ClaimUnlockedVaults is Script {

    // Contract address di Avalanche Fuji
    address constant FUM_VAULT_ADDRESS = 0x5274A2153cF842E3bD1D4996E01d567750d0e739;

    function run() external {
        // Get private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address userAddress = vm.addr(deployerPrivateKey);

        console.log("=== Claiming Unlocked Vaults ===");
        console.log("User Address:", userAddress);
        console.log("Contract Address:", FUM_VAULT_ADDRESS);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        FUMVault fumVault = FUMVault(payable(FUM_VAULT_ADDRESS));

        // Get user's vault IDs
        uint256[] memory userVaultIds = fumVault.getOwnerVaults(userAddress);

        if (userVaultIds.length == 0) {
            console.log("No vaults found for this user");
            vm.stopBroadcast();
            return;
        }

        console.log("Found", userVaultIds.length, "vault(s) for this user.");
        console.log("Checking which ones are ready for withdrawal...");
        console.log("");

        uint256 claimedCount = 0;
        uint256 totalClaimed = 0;
        uint256 failedCount = 0;

        // Check each vault and claim if unlocked
        for (uint256 i = 0; i < userVaultIds.length; i++) {
            uint256 vaultId = userVaultIds[i];

            try fumVault.getVault(vaultId) returns (FUMVault.Vault memory vault) {
                console.log("--- Processing Vault ID:", vaultId, "---");
                console.log("Amount:", vault.amount / 1e18, "ETH");
                console.log("Status:", getStatusString(vault.status));

                // Check if vault is unlocked or can be unlocked
                if (vault.status == FUMVault.VaultStatus.UNLOCKED) {
                    console.log("Vault is UNLOCKED - attempting withdrawal...");

                    try fumVault.withdrawVault(vaultId) {
                        console.log("Successfully withdrew", vault.amount / 1e18, "ETH from vault", vaultId);
                        claimedCount++;
                        totalClaimed += vault.amount;
                    } catch Error(string memory reason) {
                        console.log("Failed to withdraw vault", vaultId, "- Reason:", reason);
                        failedCount++;
                    } catch {
                        console.log("Failed to withdraw vault", vaultId, "- Unknown error");
                        failedCount++;
                    }

                } else if (vault.status == FUMVault.VaultStatus.ACTIVE) {
                    // Check if conditions are met and try to unlock + withdraw
                    try fumVault.checkConditions(vaultId) returns (bool conditionsMet) {
                        if (conditionsMet) {
                            console.log("Conditions are met - attempting withdrawal...");

                            try fumVault.withdrawVault(vaultId) {
                                console.log("Successfully unlocked and withdrew", vault.amount / 1e18, "ETH from vault", vaultId);
                                claimedCount++;
                                totalClaimed += vault.amount;
                            } catch Error(string memory reason) {
                                console.log("Failed to withdraw vault", vaultId, "- Reason:", reason);
                                failedCount++;
                            } catch {
                                console.log("Failed to withdraw vault", vaultId, "- Unknown error");
                                failedCount++;
                            }
                        } else {
                            console.log("Conditions not yet met - skipping");
                        }
                    } catch {
                        console.log("Error checking conditions for vault", vaultId);
                        failedCount++;
                    }

                } else if (vault.status == FUMVault.VaultStatus.WITHDRAWN) {
                    console.log("Already withdrawn - skipping");
                } else {
                    console.log("Status:", getStatusString(vault.status), "- skipping");
                }

                console.log("");

            } catch {
                console.log("Error reading vault", vaultId);
                failedCount++;
            }
        }

        vm.stopBroadcast();

        // Final summary
        console.log("=== CLAIM SUMMARY ===");
        console.log("Total Vaults Processed:", userVaultIds.length);
        console.log("Successfully Claimed:", claimedCount);
        console.log("Failed Claims:", failedCount);
        console.log("Total ETH Claimed:", totalClaimed / 1e18, "ETH");
        console.log("");

        if (claimedCount > 0) {
            console.log("Successfully claimed vaults:");
            console.log("Count:", claimedCount);
            console.log("Total amount:", totalClaimed / 1e18, "ETH");
        } else if (failedCount > 0) {
            console.log("No vaults were successfully claimed. Check error messages above.");
        } else {
            console.log("No vaults were ready for claiming at this time.");
        }
    }

    function getStatusString(FUMVault.VaultStatus status) internal pure returns (string memory) {
        if (status == FUMVault.VaultStatus.ACTIVE) return "ACTIVE";
        if (status == FUMVault.VaultStatus.UNLOCKED) return "UNLOCKED";
        if (status == FUMVault.VaultStatus.WITHDRAWN) return "WITHDRAWN";
        if (status == FUMVault.VaultStatus.EMERGENCY) return "EMERGENCY";
        return "UNKNOWN";
    }
}

/// @title ClaimSpecificVault - Script untuk claim vault tertentu berdasarkan ID
contract ClaimSpecificVault is Script {

    address constant FUM_VAULT_ADDRESS = 0x5274A2153cF842E3bD1D4996E01d567750d0e739;

    function run() external {
        // Get vault ID from environment
        uint256 vaultId = vm.envUint("VAULT_ID");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address userAddress = vm.addr(deployerPrivateKey);

        console.log("=== Claiming Specific Vault ===");
        console.log("User Address:", userAddress);
        console.log("Vault ID:", vaultId);
        console.log("Contract Address:", FUM_VAULT_ADDRESS);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        FUMVault fumVault = FUMVault(payable(FUM_VAULT_ADDRESS));

        // Get vault info
        try fumVault.getVault(vaultId) returns (FUMVault.Vault memory vault) {
            console.log("--- Vault Information ---");
            console.log("Owner:", vault.owner);
            console.log("Token:", vault.token == address(0) ? "ETH" : addressToString(vault.token));
            console.log("Amount:", vault.amount / 1e18, "tokens");
            console.log("Status:", getStatusString(vault.status));
            console.log("");

            // Verify ownership
            if (vault.owner != userAddress) {
                console.log("ERROR: You are not the owner of this vault!");
                console.log("Vault owner:", vault.owner);
                console.log("Your address:", userAddress);
                vm.stopBroadcast();
                return;
            }

            // Check status and attempt withdrawal
            if (vault.status == FUMVault.VaultStatus.UNLOCKED) {
                console.log("Vault is UNLOCKED - attempting withdrawal...");

                try fumVault.withdrawVault(vaultId) {
                    console.log("Successfully withdrew", vault.amount / 1e18, "tokens from vault", vaultId);
                } catch Error(string memory reason) {
                    console.log("Failed to withdraw vault - Reason:", reason);
                } catch {
                    console.log("Failed to withdraw vault - Unknown error");
                }

            } else if (vault.status == FUMVault.VaultStatus.ACTIVE) {
                console.log("Vault is ACTIVE - checking conditions...");

                try fumVault.checkConditions(vaultId) returns (bool conditionsMet) {
                    if (conditionsMet) {
                        console.log("Conditions are met - attempting withdrawal...");

                        try fumVault.withdrawVault(vaultId) {
                            console.log("Successfully unlocked and withdrew", vault.amount / 1e18, "tokens from vault", vaultId);
                        } catch Error(string memory reason) {
                            console.log("Failed to withdraw vault - Reason:", reason);
                        } catch {
                            console.log("Failed to withdraw vault - Unknown error");
                        }
                    } else {
                        console.log("Conditions not yet met - cannot withdraw");

                        // Show condition details
                        if (vault.unlockTime > 0) {
                            if (block.timestamp >= vault.unlockTime) {
                                console.log("Time Condition: MET");
                            } else {
                                console.log("Time Condition: NOT MET");
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
                    }
                } catch {
                    console.log("Error checking conditions");
                }

            } else if (vault.status == FUMVault.VaultStatus.WITHDRAWN) {
                console.log("Vault already withdrawn");
            } else {
                console.log("Vault status:", getStatusString(vault.status), "- cannot withdraw");
            }

        } catch {
            console.log("Error: Vault not found or invalid vault ID");
        }

        vm.stopBroadcast();
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
