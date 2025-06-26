// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FUMVault.sol";

/// @title Deploy F.U.M Contract to Avalanche Fuji
contract DeployFUM is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Deploying F.U.M to Avalanche Fuji ===");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy FUMVault
        FUMVault fumVault = new FUMVault(deployer);
        
        console.log("F.U.M Contract deployed successfully!");
        console.log("Contract Address:", address(fumVault));
        console.log("Owner:", fumVault.owner());
        console.log("Next Vault ID:", fumVault.nextVaultId());
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Complete ===");
        console.log("Contract Address:", address(fumVault));
        console.log("Explorer: https://testnet.snowtrace.io/address/", address(fumVault));
        console.log("\n=== Next Steps ===");
        console.log("1. export FUM_VAULT_ADDRESS=", address(fumVault));
        console.log("2. Run setup script to configure price feeds");
        console.log("3. Create test vaults");
    }
}
