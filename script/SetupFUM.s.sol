// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FUMVault.sol";

/// @title Setup F.U.M Contract - Configure Token Support & Price Feeds
contract SetupFUM is Script {
    // Avalanche Fuji Testnet Price Feed Addresses
    address constant ETH_USD_FEED = 0x86d67c3D38D2bCeE722E601025C25a575021c6EA;
    address constant AVAX_USD_FEED = 0x5498BB86BC934c8D34FDA08E81D444153d0D06aD;

    // Tokens (ETH = native via address(0), WAVAX is ERC20)
    address constant ETH_TOKEN = address(0);
    address constant WAVAX_TOKEN = 0xd00ae08403B9bbb9124bB305C09058E32C39A48c;

    function run() external {
        address fumVaultAddress = vm.envAddress("FUM_VAULT_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("=== Setting up F.U.M Vault ===\n\n");
        console.log("Contract Address:", fumVaultAddress);

        FUMVault fumVault = FUMVault(payable(fumVaultAddress));
        vm.startBroadcast(deployerPrivateKey);

        // Set token support
        console.log("\n--- Setting Supported Tokens ---");
        fumVault.setTokenSupport(ETH_TOKEN, true);
        console.log("ETH supported");

        fumVault.setTokenSupport(WAVAX_TOKEN, true);
        console.log("WAVAX supported");

        // Set price feeds
        console.log("\n--- Setting Price Feeds ---");
        fumVault.setPriceFeed(ETH_TOKEN, ETH_USD_FEED, 3600);
        console.log("ETH/USD feed set:", ETH_USD_FEED);

        fumVault.setPriceFeed(WAVAX_TOKEN, AVAX_USD_FEED, 3600);
        console.log("AVAX/USD feed set:", AVAX_USD_FEED);

        // Set automation interval
        console.log("\n--- Setting Automation Interval ---");
        fumVault.setCheckInterval(5);
        console.log("Automation interval set to 5 seconds");

        vm.stopBroadcast();
        console.log("\n Setup complete. Ready to use!");
    }
}
