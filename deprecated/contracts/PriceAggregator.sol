// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title Multi-Source Price Aggregator for Real-Time Pricing
/// @notice Combines multiple price sources to get the most up-to-date prices
contract PriceAggregator {
    
    struct PriceSource {
        AggregatorV3Interface feed;
        uint256 heartbeat;
        uint256 weight; // Weight for averaging (1-100)
        bool isActive;
    }
    
    mapping(address => PriceSource[]) public priceSources;
    
    error NoPriceSourcesAvailable();
    error AllPriceSourcesStale();
    
    /// @notice Add a price source for a token
    function addPriceSource(
        address token,
        address priceFeed,
        uint256 heartbeat,
        uint256 weight
    ) external {
        priceSources[token].push(PriceSource({
            feed: AggregatorV3Interface(priceFeed),
            heartbeat: heartbeat,
            weight: weight,
            isActive: true
        }));
    }
    
    /// @notice Get the most up-to-date price using multiple sources
    function getLatestPrice(address token) external view returns (uint256 price, uint256 confidence) {
        PriceSource[] memory sources = priceSources[token];
        if (sources.length == 0) revert NoPriceSourcesAvailable();
        
        uint256 totalWeight = 0;
        uint256 weightedSum = 0;
        uint256 freshSources = 0;
        
        for (uint256 i = 0; i < sources.length; i++) {
            if (!sources[i].isActive) continue;
            
            try sources[i].feed.latestRoundData() returns (
                uint80,
                int256 answer,
                uint256,
                uint256 updatedAt,
                uint80
            ) {
                if (answer <= 0) continue;
                
                uint256 timeSinceUpdate = block.timestamp - updatedAt;
                
                // Use fresh data (within heartbeat)
                if (timeSinceUpdate <= sources[i].heartbeat) {
                    weightedSum += uint256(answer) * sources[i].weight;
                    totalWeight += sources[i].weight;
                    freshSources++;
                }
                // Use stale data with reduced weight if no fresh data available
                else if (totalWeight == 0 && timeSinceUpdate <= sources[i].heartbeat * 2) {
                    weightedSum += uint256(answer) * (sources[i].weight / 2);
                    totalWeight += (sources[i].weight / 2);
                }
            } catch {
                continue;
            }
        }
        
        if (totalWeight == 0) revert AllPriceSourcesStale();
        
        price = weightedSum / totalWeight;
        confidence = (freshSources * 100) / sources.length; // Confidence percentage
    }
    
    /// @notice Get the fastest updating price source
    function getFastestPrice(address token) external view returns (uint256 price, uint256 lastUpdate) {
        PriceSource[] memory sources = priceSources[token];
        if (sources.length == 0) revert NoPriceSourcesAvailable();
        
        uint256 latestUpdate = 0;
        uint256 latestPrice = 0;
        
        for (uint256 i = 0; i < sources.length; i++) {
            if (!sources[i].isActive) continue;
            
            try sources[i].feed.latestRoundData() returns (
                uint80,
                int256 answer,
                uint256,
                uint256 updatedAt,
                uint80
            ) {
                if (answer <= 0) continue;
                
                // Find the most recently updated source
                if (updatedAt > latestUpdate) {
                    latestUpdate = updatedAt;
                    latestPrice = uint256(answer);
                }
            } catch {
                continue;
            }
        }
        
        if (latestUpdate == 0) revert AllPriceSourcesStale();
        
        return (latestPrice, latestUpdate);
    }
}
