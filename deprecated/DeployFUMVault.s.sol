// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FUMVault.sol";
import "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title FUMVault Deployment Script
/// @notice Deploys FUMVault with proper Chainlink price feed configuration
contract DeployFUMVault is Script {

    // Network-specific price feed addresses
    struct NetworkConfig {
        // address ethUsdPriceFeed;
        address btcUsdPriceFeed;
        address linkUsdPriceFeed;
        uint256 priceFeedHeartbeat;
        string name;
    }

    // Mainnet price feeds
    address constant MAINNET_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant MAINNET_BTC_USD = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address constant MAINNET_LINK_USD = 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c;

    // Sepolia testnet price feeds
    address constant SEPOLIA_ETH_USD = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address constant SEPOLIA_BTC_USD = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
    address constant SEPOLIA_LINK_USD = 0xc59E3633BAAC79493d908e63626716e204A45EdF;

    // Base Sepolia testnet price feeds
    address constant BASE_SEPOLIA_ETH_USD = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;
    address constant BASE_SEPOLIA_BTC_USD = 0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298;

    // Avalanche Fuji testnet price feeds (Verified working addresses)
    address constant FUJI_ETH_USD = 0x86d67c3D38D2bCeE722E601025C25a575021c6EA;
    address constant FUJI_BTC_USD = 0x31CF013A08c6Ac228C94551d535d5BAfE19c602a;
    address constant FUJI_AVAX_USD = 0x5498BB86BC934c8D34FDA08E81D444153d0D06aD;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying FUMVault...");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        NetworkConfig memory config = getNetworkConfig();
        console.log("Network:", config.name);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy FUMVault
        FUMVault fumVault = new FUMVault(deployer);

        console.log("FUMVault deployed at:", address(fumVault));

        // Configure price feeds if available with error handling
        // if (config.ethUsdPriceFeed != address(0)) {
        //     console.log("Attempting to configure ETH/USD price feed:", config.ethUsdPriceFeed);

        //     try fumVault.setPriceFeed(address(0), config.ethUsdPriceFeed, config.priceFeedHeartbeat) {
        //         console.log("[SUCCESS] ETH/USD price feed configured");

        //         // Test the price feed immediately
        //         try fumVault.getCurrentPrice(address(0)) returns (uint256 price) {
        //             console.log("[SUCCESS] ETH/USD price feed working! Current price:", price);
        //         } catch {
        //             console.log("[WARNING] ETH/USD price feed configured but failed to fetch price");
        //         }
        //     } catch {
        //         console.log("[ERROR] Failed to configure ETH/USD price feed - address may be invalid");
        //         console.log("Skipping ETH/USD price feed configuration");
        //     }
        // }

        if (config.btcUsdPriceFeed != address(0)) {
            console.log("BTC/USD price feed available:", config.btcUsdPriceFeed);

            // Test BTC price feed
            AggregatorV3Interface btcFeed = AggregatorV3Interface(config.btcUsdPriceFeed);
            try btcFeed.latestRoundData() returns (uint80, int256 price, uint256, uint256, uint80) {
                console.log("[SUCCESS] BTC/USD price feed working! Current price:", uint256(price));
            } catch {
                console.log("[ERROR] BTC/USD price feed failed");
            }
        }

        if (config.linkUsdPriceFeed != address(0)) {
            console.log("LINK/USD price feed available:", config.linkUsdPriceFeed);

            // Test LINK price feed
            AggregatorV3Interface linkFeed = AggregatorV3Interface(config.linkUsdPriceFeed);
            try linkFeed.latestRoundData() returns (uint80, int256 price, uint256, uint256, uint80) {
                console.log("[SUCCESS] LINK/USD price feed working! Current price:", uint256(price));
            } catch {
                console.log("[ERROR] LINK/USD price feed failed");
            }
        }

        vm.stopBroadcast();

        console.log("Deployment completed successfully!");
        console.log("Contract address:", address(fumVault));
        console.log("Owner:", fumVault.owner());
        console.log("Next vault ID:", fumVault.nextVaultId());

        // Verify price feeds
        // if (config.ethUsdPriceFeed != address(0)) {
        //     (address priceFeed, uint256 heartbeat, uint8 decimals) = fumVault.getPriceFeedInfo(address(0));
        //     console.log("ETH price feed info:");
        //     console.log("  Address:", priceFeed);
        //     console.log("  Heartbeat:", heartbeat);
        //     console.log("  Decimals:", decimals);

        //     try fumVault.getCurrentPrice(address(0)) returns (uint256 price) {
        //         console.log("  Current ETH price:", price);
        //     } catch {
        //         console.log("  Could not fetch current ETH price");
        //     }
        // }
    }

    function getNetworkConfig() internal view returns (NetworkConfig memory) {
        uint256 chainId = block.chainid;

        if (chainId == 1) {
            // Ethereum Mainnet
            return NetworkConfig({
                // ethUsdPriceFeed: MAINNET_ETH_USD,
                btcUsdPriceFeed: MAINNET_BTC_USD,
                linkUsdPriceFeed: MAINNET_LINK_USD,
                priceFeedHeartbeat: 3600, // 1 hour
                name: "Ethereum Mainnet"
            });
        } else if (chainId == 11155111) {
            // Sepolia Testnet
            return NetworkConfig({
                // ethUsdPriceFeed: SEPOLIA_ETH_USD,
                btcUsdPriceFeed: SEPOLIA_BTC_USD,
                linkUsdPriceFeed: SEPOLIA_LINK_USD,
                priceFeedHeartbeat: 3600, // 1 hour
                name: "Sepolia Testnet"
            });
        } else if (chainId == 84532) {
            // Base Sepolia Testnet
            return NetworkConfig({
                // ethUsdPriceFeed: BASE_SEPOLIA_ETH_USD,
                btcUsdPriceFeed: BASE_SEPOLIA_BTC_USD,
                linkUsdPriceFeed: address(0), // Not available
                priceFeedHeartbeat: 3600, // 1 hour
                name: "Base Sepolia Testnet"
            });
        } else if (chainId == 43113) {
            // Avalanche Fuji Testnet
            return NetworkConfig({
                // ethUsdPriceFeed: FUJI_ETH_USD, // Not available
                btcUsdPriceFeed: FUJI_BTC_USD,
                linkUsdPriceFeed: FUJI_AVAX_USD, // Using AVAX/USD as alternative
                priceFeedHeartbeat: 3600, // 1 hour
                name: "Avalanche Fuji Testnet"
            });
        } else if (chainId == 31337) {
            // Local Anvil
            return NetworkConfig({
                // ethUsdPriceFeed: address(0), // Will be deployed in tests
                btcUsdPriceFeed: address(0),
                linkUsdPriceFeed: address(0),
                priceFeedHeartbeat: 3600,
                name: "Local Anvil"
            });
        } else {
            // Default/Unknown network
            return NetworkConfig({
                // ethUsdPriceFeed: address(0),
                btcUsdPriceFeed: address(0),
                linkUsdPriceFeed: address(0),
                priceFeedHeartbeat: 3600,
                name: "Unknown Network"
            });
        }
    }

    /// @notice Helper function to deploy mock price feeds for testing
    function deployMockPriceFeeds() external returns (address ethFeed, address btcFeed) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock price feeds (only for testing)
        // Note: You'll need to import MockV3Aggregator for this to work
        // MockV3Aggregator ethPriceFeed = new MockV3Aggregator(8, 2000 * 10**8);
        // MockV3Aggregator btcPriceFeed = new MockV3Aggregator(8, 50000 * 10**8);

        vm.stopBroadcast();

        // return (address(ethPriceFeed), address(btcPriceFeed));
        return (address(0), address(0)); // Placeholder
    }
}
