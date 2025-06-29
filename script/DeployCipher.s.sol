// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/CipherVault.sol";

/// @title Deploy Cipher Contract to Avalanche Fuji
contract DeployCipher is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Deploying Cipher to Avalanche Fuji ===");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy CipherVault
        CipherVault cipherVault = new CipherVault(deployer);
        
        console.log("Cipher Contract deployed successfully!");
        console.log("Contract Address:", address(cipherVault));
        console.log("Owner:", cipherVault.owner());
        console.log("Next Vault ID:", cipherVault.nextVaultId());
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Complete ===");
        console.log("Contract Address:", address(cipherVault));
        console.log("Explorer: https://testnet.snowtrace.io/address/", address(cipherVault));
        console.log("\n=== Next Steps ===");
        console.log("1. export CIPHER_VAULT_ADDRESS=", address(cipherVault));
        console.log("2. Run setup script to configure price feeds");
        console.log("3. Create test vaults");
    }
}
