#!/bin/bash

# FUMVault Contract Verification Script for Avalanche Fuji
# Contract Address: 0xc1A4202a146Ff01D756cb180eCC03a7daf7Ae9f5

echo "🔍 Verifying FUMVault Contract on Avalanche Fuji..."
echo "Contract Address: 0xc1A4202a146Ff01D756cb180eCC03a7daf7Ae9f5"
echo "Owner Address: 0x1B2FC03AD5405347a60b407929633FFc544f1Db6"
echo ""

# Step 1: Generate constructor arguments
echo "📝 Step 1: Generating constructor arguments..."
CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address)" 0x1B2FC03AD5405347a60b407929633FFc544f1Db6)
echo "Constructor Args: $CONSTRUCTOR_ARGS"
echo ""

# Step 2: Verify contract
echo "🚀 Step 2: Verifying contract..."
echo "Running verification command..."
echo ""

forge verify-contract \
    0xc1A4202a146Ff01D756cb180eCC03a7daf7Ae9f5 \
    src/FUMVault.sol:FUMVault \
    --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/43113/etherscan' \
    --etherscan-api-key "verifyContract" \
    --num-of-optimizations 200 \
    --compiler-version v0.8.24+commit.e11b9ed9 \
    --constructor-args $CONSTRUCTOR_ARGS

echo ""
echo "✅ Verification command executed!"
echo ""
echo "📋 Verification Details:"
echo "- Contract: src/FUMVault.sol:FUMVault"
echo "- Address: 0xc1A4202a146Ff01D756cb180eCC03a7daf7Ae9f5"
echo "- Network: Avalanche Fuji (Chain ID: 43113)"
echo "- Verifier: RoutesScan"
echo "- Compiler: v0.8.24+commit.e11b9ed9"
echo "- Optimizations: 200"
echo ""
echo "🌐 Check verification status at:"
echo "https://testnet.snowtrace.io/address/0xc1A4202a146Ff01D756cb180eCC03a7daf7Ae9f5"
echo ""
echo "📖 If verification successful, you can:"
echo "1. Read contract functions on Snowtrace"
echo "2. Write contract functions on Snowtrace"
echo "3. View contract source code"
echo "4. See all contract events and transactions"
