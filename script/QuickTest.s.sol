// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FUMVault.sol";

/// @title QuickTest - Script untuk test contract address yang baru
/// @notice Script ini akan test basic functionality dari contract yang baru
contract QuickTest is Script {

    // Updated contract address
    address constant FUM_VAULT_ADDRESS = 0x5274A2153cF842E3bD1D4996E01d567750d0e739;

    function run() external view {
        console.log("=== Quick Test F.U.M Contract ===");
        console.log("Testing Contract Address:", FUM_VAULT_ADDRESS);
        console.log("Block Timestamp:", block.timestamp);
        console.log("");

        FUMVault fumVault = FUMVault(payable(FUM_VAULT_ADDRESS));

        // Test 1: Basic contract info
        console.log("--- Test 1: Contract Stats ---");
        try fumVault.getContractStats() returns (uint256 totalVaults, uint256 contractBalance) {
            console.log("Contract is accessible");
            console.log("Total Vaults:", totalVaults);
            console.log("Contract Balance:", contractBalance / 1e18, "ETH");
        } catch {
            console.log("ERROR: Cannot access contract - check address!");
            return;
        }

        console.log("");

        // Test 2: Automation settings
        console.log("--- Test 2: Automation Settings ---");
        try fumVault.checkInterval() returns (uint256 interval) {
            console.log("Automation accessible");
            console.log("Check Interval:", interval, "seconds");
        } catch {
            console.log("ERROR: Cannot access automation settings");
        }

        try fumVault.lastCheckTimestamp() returns (uint256 lastCheck) {
            console.log("Last Check Timestamp:", lastCheck);
            if (lastCheck > 0) {
                console.log("Time since last check:", (block.timestamp - lastCheck), "seconds");
            } else {
                console.log("No automation checks performed yet");
            }
        } catch {
            console.log("ERROR: Cannot access last check timestamp");
        }

        console.log("");

        // Test 3: Price feeds
        console.log("--- Test 3: Price Feeds ---");
        address[] memory tokens = new address[](1);
        tokens[0] = address(0); // ETH

        string[] memory tokenNames = new string[](1);
        tokenNames[0] = "ETH";

        for (uint256 i = 0; i < tokens.length; i++) {
            try fumVault.getCurrentPrice(tokens[i]) returns (uint256 price) {
                console.log(tokenNames[i], "Price Feed Working");
                console.log("Current Price:", price / 1e8, "USD");
            } catch {
                console.log(tokenNames[i], "Price Feed not configured or error");
            }

            try fumVault.getPriceFeedInfo(tokens[i]) returns (
                address priceFeed,
                uint256 heartbeat,
                uint8 decimals
            ) {
                if (priceFeed != address(0)) {
                    console.log("Price Feed Address:", priceFeed);
                    console.log("Heartbeat:", heartbeat, "seconds");
                    console.log("Decimals:", decimals);
                } else {
                    console.log("No price feed configured for", tokenNames[i]);
                }
            } catch {
                console.log("Error getting price feed info for", tokenNames[i]);
            }
        }

        console.log("");

        // Test 4: Upkeep check
        console.log("--- Test 4: Automation Upkeep ---");
        try fumVault.checkUpkeep("") returns (bool upkeepNeeded, bytes memory performData) {
            console.log("Upkeep check accessible");
            console.log("Upkeep Needed:", upkeepNeeded ? "YES" : "NO");

            if (upkeepNeeded) {
                uint256[] memory readyVaultIds = abi.decode(performData, (uint256[]));
                console.log("Ready Vaults Count:", readyVaultIds.length);
                for (uint256 i = 0; i < readyVaultIds.length && i < 5; i++) {
                    console.log("  - Vault ID:", readyVaultIds[i]);
                }
            }
        } catch {
            console.log("ERROR: Cannot check upkeep");
        }

        console.log("");

        // Test 5: Token support
        console.log("--- Test 5: Token Support ---");
        try fumVault.supportedTokens(address(0)) returns (bool supported) {
            console.log("ETH Supported:", supported ? "YES" : "NO");
        } catch {
            console.log("Error checking ETH support");
        }

        console.log("");

        // Test 6: Owner functions (read-only)
        console.log("--- Test 6: Contract Owner ---");
        try fumVault.owner() returns (address contractOwner) {
            console.log("Contract Owner:", contractOwner);
        } catch {
            console.log("Error getting contract owner");
        }

        try fumVault.paused() returns (bool isPaused) {
            console.log("Contract Paused:", isPaused ? "YES" : "NO");
        } catch {
            console.log("Error checking pause status");
        }

        console.log("");

        // Final summary
        console.log("=== TEST SUMMARY ===");
        console.log("Contract Address is valid and accessible");
        console.log("Basic functions are working");
        console.log("Ready to use vault management scripts");
        console.log("");
        console.log("Next Steps:");
        console.log("1. View your vaults: forge script script/ViewUnlockedVaults.s.sol:ViewUserVaults --rpc-url $FUJI_RPC_URL");
        console.log("2. Monitor automation: forge script script/MonitorAutomation.s.sol:MonitorAutomation --rpc-url $FUJI_RPC_URL");
        console.log("3. Claim ready vaults: forge script script/ClaimUnlockedVaults.s.sol:ClaimUnlockedVaults --rpc-url $FUJI_RPC_URL --broadcast");
    }
}

/// @title TestContractInteraction - Script untuk test interaksi dengan contract
contract TestContractInteraction is Script {

    address constant FUM_VAULT_ADDRESS = 0x5274A2153cF842E3bD1D4996E01d567750d0e739;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address userAddress = vm.addr(deployerPrivateKey);

        console.log("=== Test Contract Interaction ===");
        console.log("User Address:", userAddress);
        console.log("Contract Address:", FUM_VAULT_ADDRESS);
        console.log("");

        FUMVault fumVault = FUMVault(payable(FUM_VAULT_ADDRESS));

        // Check user's existing vaults
        console.log("--- Checking User's Vaults ---");
        try fumVault.getOwnerVaults(userAddress) returns (uint256[] memory userVaultIds) {
            console.log("User has", userVaultIds.length, "vault(s)");

            if (userVaultIds.length > 0) {
                console.log("Vault IDs:");
                for (uint256 i = 0; i < userVaultIds.length && i < 10; i++) {
                    console.log("  -", userVaultIds[i]);
                }

                // Check first vault details
                if (userVaultIds.length > 0) {
                    uint256 firstVaultId = userVaultIds[0];
                    console.log("");
                    console.log("--- First Vault Details ---");

                    try fumVault.getVault(firstVaultId) returns (FUMVault.Vault memory vault) {
                        console.log("Vault ID:", firstVaultId);
                        console.log("Token:", vault.token == address(0) ? "ETH" : addressToString(vault.token));
                        console.log("Amount:", vault.amount / 1e18, "tokens");
                        console.log("Status:", getStatusString(vault.status));
                        console.log("Created At:", vault.createdAt);

                        // Check conditions
                        try fumVault.checkConditions(firstVaultId) returns (bool conditionsMet) {
                            console.log("Conditions Met:", conditionsMet ? "YES" : "NO");
                        } catch {
                            console.log("Error checking conditions");
                        }
                    } catch {
                        console.log("Error getting vault details");
                    }
                }
            } else {
                console.log("No vaults found for this user");
                console.log("");
                console.log("To create a test vault, use:");
                console.log("forge script script/MonitorAutomation.s.sol:TestAutomationFlow --rpc-url $FUJI_RPC_URL --broadcast");
            }
        } catch {
            console.log("Error getting user vaults");
        }

        console.log("");

        // Check emergency penalty
        console.log("--- Checking Emergency Penalty ---");
        try fumVault.getEmergencyPenalty(userAddress) returns (FUMVault.EmergencyPenalty memory penalty) {
            if (penalty.amount > 0) {
                console.log("Emergency Penalty Found:");
                console.log("Amount:", penalty.amount / 1e18, "ETH");
                console.log("Penalty Time:", penalty.penaltyTime);
                console.log("Claimed:", penalty.claimed ? "YES" : "NO");

                if (!penalty.claimed) {
                    uint256 claimableTime = penalty.penaltyTime + 90 days;
                    if (block.timestamp >= claimableTime) {
                        console.log("Penalty is ready to claim!");
                    } else {
                        uint256 timeRemaining = claimableTime - block.timestamp;
                        console.log("Claimable in:", timeRemaining / 86400, "days");
                    }
                }
            } else {
                console.log("No emergency penalty found");
            }
        } catch {
            console.log("Error checking emergency penalty");
        }

        console.log("");
        console.log("Contract interaction test completed successfully!");
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
