// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FUMVault.sol";

/// @title EmergencyWithdrawal - Script untuk emergency withdrawal dengan penalty 10%
/// @notice Script ini akan melakukan emergency withdrawal dari vault tertentu
contract EmergencyWithdrawal is Script {

    address constant FUM_VAULT_ADDRESS = 0x5274A2153cF842E3bD1D4996E01d567750d0e739;

    function run() external {
        // Get vault ID from environment
        uint256 vaultId = vm.envUint("VAULT_ID");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address userAddress = vm.addr(deployerPrivateKey);

        console.log("=== Emergency Withdrawal ===");
        console.log("WARNING: This will incur a 10% penalty!");
        console.log("User Address:", userAddress);
        console.log("Vault ID:", vaultId);
        console.log("Contract Address:", FUM_VAULT_ADDRESS);
        console.log("");

        FUMVault fumVault = FUMVault(payable(FUM_VAULT_ADDRESS));

        // Get vault info first
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
                return;
            }

            // Check if vault is active
            if (vault.status != FUMVault.VaultStatus.ACTIVE) {
                console.log("ERROR: Vault is not active. Current status:", getStatusString(vault.status));
                return;
            }

            // Calculate penalty
            uint256 penalty = fumVault.calculateEmergencyPenalty(vault.amount);
            uint256 withdrawAmount = vault.amount - penalty;

            console.log("--- Emergency Withdrawal Details ---");
            console.log("Original Amount:", vault.amount / 1e18, "ETH");
            console.log("Penalty (10%):", penalty / 1e18, "ETH");
            console.log("You will receive:", withdrawAmount / 1e18, "ETH");
            console.log("Penalty will be claimable after 3 months");
            console.log("");

            // Confirm before proceeding (in real usage, you might want manual confirmation)
            console.log("Proceeding with emergency withdrawal...");

            vm.startBroadcast(deployerPrivateKey);

            try fumVault.executeEmergencyWithdrawal(vaultId) {
                console.log("Emergency withdrawal successful!");
                console.log("Received:", withdrawAmount / 1e18, "ETH");
                console.log("Penalty of", penalty / 1e18, "ETH will be claimable after 3 months");
            } catch Error(string memory reason) {
                console.log("Emergency withdrawal failed - Reason:", reason);
            } catch {
                console.log("Emergency withdrawal failed - Unknown error");
            }

            vm.stopBroadcast();

        } catch {
            console.log("Error: Vault not found or invalid vault ID");
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

/// @title ClaimEmergencyPenalty - Script untuk claim penalty setelah 3 bulan
/// @notice Script ini akan claim penalty dari emergency withdrawal setelah 3 bulan
contract ClaimEmergencyPenalty is Script {

    address constant FUM_VAULT_ADDRESS = 0x5274A2153cF842E3bD1D4996E01d567750d0e739;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address userAddress = vm.addr(deployerPrivateKey);

        console.log("=== Claim Emergency Penalty ===");
        console.log("User Address:", userAddress);
        console.log("Contract Address:", FUM_VAULT_ADDRESS);
        console.log("");

        FUMVault fumVault = FUMVault(payable(FUM_VAULT_ADDRESS));

        // Get penalty info
        try fumVault.getEmergencyPenalty(userAddress) returns (FUMVault.EmergencyPenalty memory penalty) {
            console.log("--- Penalty Information ---");
            console.log("Penalty Amount:", penalty.amount / 1e18, "ETH");
            console.log("Penalty Time:", penalty.penaltyTime);
            console.log("Already Claimed:", penalty.claimed ? "YES" : "NO");
            console.log("");

            if (penalty.amount == 0) {
                console.log("No penalty available to claim.");
                return;
            }

            if (penalty.claimed) {
                console.log("Penalty already claimed.");
                return;
            }

            // Check if 3 months have passed
            uint256 claimableTime = penalty.penaltyTime + 90 days; // PENALTY_CLAIM_DELAY
            uint256 currentTime = block.timestamp;

            console.log("Current Time:", currentTime);
            console.log("Claimable Time:", claimableTime);

            if (currentTime < claimableTime) {
                uint256 timeRemaining = claimableTime - currentTime;
                console.log("Penalty not yet claimable.");
                console.log("Time remaining (days):", timeRemaining / 86400);
                console.log("Time remaining (hours):", (timeRemaining % 86400) / 3600);
                return;
            }

            console.log("Penalty is ready to claim!");
            console.log("Attempting to claim", penalty.amount / 1e18, "ETH...");

            vm.startBroadcast(deployerPrivateKey);

            try fumVault.claimEmergencyPenalty() {
                console.log("Successfully claimed penalty of", penalty.amount / 1e18, "ETH!");
            } catch Error(string memory reason) {
                console.log("Failed to claim penalty - Reason:", reason);
            } catch {
                console.log("Failed to claim penalty - Unknown error");
            }

            vm.stopBroadcast();

        } catch {
            console.log("Error getting penalty information");
        }
    }
}

/// @title CheckEmergencyPenalty - Script untuk check status penalty tanpa claim
contract CheckEmergencyPenalty is Script {

    address constant FUM_VAULT_ADDRESS = 0x5274A2153cF842E3bD1D4996E01d567750d0e739;

    function run() external view {
        // Get user address from environment or use msg.sender
        address userAddress = vm.envOr("USER_ADDRESS", msg.sender);

        console.log("=== Check Emergency Penalty Status ===");
        console.log("User Address:", userAddress);
        console.log("Contract Address:", FUM_VAULT_ADDRESS);
        console.log("");

        FUMVault fumVault = FUMVault(payable(FUM_VAULT_ADDRESS));

        try fumVault.getEmergencyPenalty(userAddress) returns (FUMVault.EmergencyPenalty memory penalty) {
            console.log("--- Penalty Information ---");
            console.log("Penalty Amount:", penalty.amount / 1e18, "ETH");

            if (penalty.amount == 0) {
                console.log("No emergency penalty found for this address.");
                return;
            }

            console.log("Penalty Time:", penalty.penaltyTime);
            console.log("Already Claimed:", penalty.claimed ? "YES" : "NO");

            if (penalty.claimed) {
                console.log("Penalty has been claimed.");
                return;
            }

            // Check claimability
            uint256 claimableTime = penalty.penaltyTime + 90 days;
            uint256 currentTime = block.timestamp;

            console.log("");
            console.log("--- Claimability Status ---");
            console.log("Current Time:", currentTime);
            console.log("Claimable Time:", claimableTime);

            if (currentTime >= claimableTime) {
                console.log("PENALTY IS READY TO CLAIM!");
                console.log("Run: VAULT_ID=X forge script script/EmergencyOperations.s.sol:ClaimEmergencyPenalty --rpc-url $FUJI_RPC_URL --broadcast");
            } else {
                uint256 timeRemaining = claimableTime - currentTime;
                console.log("Penalty not yet claimable.");
                console.log("Time remaining (days):", timeRemaining / 86400);
                console.log("Time remaining (hours):", (timeRemaining % 86400) / 3600);
                console.log("Time remaining (minutes):", (timeRemaining % 3600) / 60);
            }

        } catch {
            console.log("Error getting penalty information");
        }
    }
}
