// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

/// @title Verify FUMVault Contract on Avalanche Fuji
contract VerifyContract is Script {
    
    // Contract details
    address constant CONTRACT_ADDRESS = 0xc1A4202a146Ff01D756cb180eCC03a7daf7Ae9f5;
    address constant OWNER_ADDRESS = 0x1B2FC03AD5405347a60b407929633FFc544f1Db6;
    
    function run() external view {
        console.log("=== FUMVault Contract Verification Guide ===");
        console.log("Contract Address:", CONTRACT_ADDRESS);
        console.log("Owner Address:", OWNER_ADDRESS);
        console.log("Network: Avalanche Fuji Testnet");
        console.log("Chain ID: 43113");
        
        console.log("\n=== Verification Command ===");
        console.log("Copy and paste this command:");
        console.log("");
        
        // Generate the verification command
        string memory verifyCommand = string.concat(
            "forge verify-contract ",
            "0xc1A4202a146Ff01D756cb180eCC03a7daf7Ae9f5 ",
            "src/FUMVault.sol:FUMVault ",
            "--verifier-url 'https://api.routescan.io/v2/network/testnet/evm/43113/etherscan' ",
            "--etherscan-api-key 'verifyContract' ",
            "--num-of-optimizations 200 ",
            "--compiler-version v0.8.24+commit.e11b9ed9 ",
            "--constructor-args $(cast abi-encode 'constructor(address)' 0x1B2FC03AD5405347a60b407929633FFc544f1Db6)"
        );
        
        console.log(verifyCommand);
        
        console.log("\n=== Alternative Manual Command ===");
        console.log("If the above doesn't work, try this step-by-step:");
        console.log("");
        console.log("1. Generate constructor args:");
        console.log("cast abi-encode 'constructor(address)' 0x1B2FC03AD5405347a60b407929633FFc544f1Db6");
        console.log("");
        console.log("2. Use the output in verification command");
        
        console.log("\n=== Verification Details ===");
        console.log("Contract Path: src/FUMVault.sol:FUMVault");
        console.log("Verifier URL: https://api.routescan.io/v2/network/testnet/evm/43113/etherscan");
        console.log("API Key: verifyContract");
        console.log("Optimizations: 200");
        console.log("Compiler: v0.8.24+commit.e11b9ed9");
        console.log("Constructor Args: address owner = 0x1B2FC03AD5405347a60b407929633FFc544f1Db6");
    }
}
