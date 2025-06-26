# 🚀 F.U.M Vault - Fund Ur Memory

> **"Set It, Forget It, Let AI Remember It – Your Cross-Chain Autonomous Wealth Vault"**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)
[![Chainlink](https://img.shields.io/badge/Powered%20by-Chainlink-375BD2.svg)](https://chain.link/)

F.U.M Vault is a revolutionary DeFi protocol that implements **"Commitment Contracts"** - smart contracts that enforce your future self's rational decisions by removing present-day emotions from trading decisions.

## 🌟 Key Features

- ⏰ **Time-based Commitments**: Lock assets until a specific time
- 💰 **Price-based Commitments**: Unlock when target prices are reached
- 🔄 **Combined Conditions**: Mix time and price conditions with AND/OR logic
- 📊 **Price Range Vaults**: Unlock when price is within a specific range
- 🤖 **Chainlink Automation**: Fully automated condition monitoring
- 🌐 **Cross-chain Support**: CCIP integration for multi-chain operations
- 🛡️ **Emergency Withdrawals**: Safety mechanism with penalty system
- 📈 **Real-time Price Feeds**: Chainlink price feeds with validation
- 🔒 **Security First**: Comprehensive security measures and testing

## 🏗️ Architecture

```
FUMVault (Main Contract)
├── FUMVaultCore (Base functionality)
├── ChainlinkPriceFeedModule (Price data)
├── ChainlinkAutomationModule (Automated execution)
└── ChainlinkCCIPModule (Cross-chain operations)
```

## 🚀 Quick Start

### Prerequisites

- [Foundry](https://getfoundry.sh/) installed
- Node.js 16+ for frontend
- Git

### Installation

```bash
# Clone the repository
git clone https://github.com/your-org/fund-ur-memory.git
cd fund-ur-memory/fund-ur-memory-contract

# Install dependencies
forge install

# Copy environment file
cp .env.example .env
# Edit .env with your configuration
```

### Build and Test

```bash
# Build contracts
forge build

# Run tests
forge test

# Run tests with verbose output
forge test -vv

# Run tests with gas reporting
forge test --gas-report

# Generate coverage report
forge coverage
```

**✅ Test Results - All 27 Tests Passing!**
```
Ran 27 tests for test/FUMVault.t.sol:FUMVaultTest
[PASS] testCheckUpkeepNoVaults() (gas: 13490)
[PASS] testCheckUpkeepWithReadyVaults() (gas: 325032)
[PASS] testCreatePriceVault() (gas: 206180)
[PASS] testCreateTimeVault() (gas: 186230)
[PASS] testCreateTokenVault() (gas: 231798)
[PASS] testEmergencyWithdrawal() (gas: 314359)
[PASS] testFullWorkflowPriceVault() (gas: 294616)
[PASS] testFullWorkflowTimeVault() (gas: 199683)
[PASS] testPerformUpkeep() (gas: 211525)
[PASS] testPriceConditionMet() (gas: 306242)
[PASS] testTimeConditionMet() (gas: 180212)
[PASS] testWithdrawVault() (gas: 201800)
... and 15 more tests covering edge cases and error conditions
Suite result: ok. 27 passed; 0 failed; 0 skipped
```

**Test Coverage:**
- ✅ Basic functionality (deployment, configuration)
- ✅ Vault creation (all condition types)
- ✅ Condition checking (time, price, combined)
- ✅ Vault operations (withdraw, emergency)
- ✅ Chainlink automation (checkUpkeep, performUpkeep)
- ✅ Price feed validation (staleness, decimals)
- ✅ Error conditions (invalid inputs, permissions)
- ✅ Integration workflows (end-to-end)

### Deploy

```bash
# Deploy to Sepolia testnet
forge script script/DeployFUMVault.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify

# Deploy to mainnet
forge script script/DeployFUMVault.s.sol --rpc-url $ETH_RPC_URL --broadcast --verify
```

## 💡 Usage Examples

### Create a Time-based Vault

```solidity
// Lock 1 ETH for 30 days
uint256 vaultId = fumVault.createTimeVaultWithAutomation{value: 1 ether}(
    address(0), // ETH
    1 ether,
    block.timestamp + 30 days,
    true, // Enable automation
    "HODL for 30 days - resist FOMO!"
);
```

### Create a Price-based Vault

```solidity
// Lock ETH until it reaches $5000
uint256 vaultId = fumVault.createPriceVaultWithAutomation{value: 1 ether}(
    address(0), // ETH
    1 ether,
    5000e8, // $5000 target (8 decimals)
    true, // Enable automation
    "Sell when ETH hits $5000"
);
```

### Create a Combined Vault

```solidity
// Lock for 7 days OR until ETH hits $4000
uint256 vaultId = fumVault.createCombinedVault{value: 1 ether}(
    address(0), // ETH
    1 ether,
    block.timestamp + 7 days,
    4000e8, // $4000 target
    FUMVaultCore.ConditionType.TIME_OR_PRICE,
    true, // Enable automation
    "Exit in 1 week or at $4000"
);
```

## 🔗 Chainlink Integration

### Price Feeds
- Real-time price data from Chainlink oracles
- Built-in validation and circuit breakers
- Support for ETH/USD, BTC/USD, and other major pairs
- Fallback mechanisms for resilience

### Automation
- 24/7 automated vault condition monitoring
- Gas-optimized batch processing
- Configurable check intervals and limits
- Performance tracking and metrics

### CCIP (Cross-Chain)
- Cross-chain vault creation and management
- Real-time status synchronization
- Secure asset bridging
- Multi-chain configuration support

## 📊 Supported Networks

| Network | Chain ID | Status | Price Feeds | Automation | CCIP |
|---------|----------|--------|-------------|------------|------|
| Ethereum Mainnet | 1 | ✅ | ✅ | ✅ | ✅ |
| Ethereum Sepolia | 11155111 | ✅ | ✅ | ✅ | ✅ |
| Polygon | 137 | ✅ | ✅ | ✅ | ✅ |
| Arbitrum One | 42161 | ✅ | ✅ | ✅ | ✅ |
| Base | 8453 | ✅ | ✅ | ✅ | ✅ |
| Avalanche C-Chain | 43114 | ✅ | ✅ | ✅ | ✅ |

## 🧪 Testing

The project includes comprehensive tests covering:

- ✅ Vault creation with different condition types
- ✅ Time-based and price-based unlocking
- ✅ Emergency withdrawal system
- ✅ Price feed validation and circuit breakers
- ✅ Automation condition checking
- ✅ Access control and security
- ✅ Fee calculation and distribution
- ✅ Edge cases and error handling

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-contract FUMVaultCompleteTest

# Run with verbosity for debugging
forge test -vvv

# Generate coverage report
forge coverage --report lcov
```

## 🛡️ Security

### Security Measures
- **ReentrancyGuard**: Protection against reentrancy attacks
- **Access Control**: Proper role-based permissions
- **Input Validation**: Comprehensive parameter checking
- **Circuit Breakers**: Price feed anomaly detection
- **Emergency Pause**: Contract-wide pause functionality

### Audits
- [ ] Internal security review completed
- [ ] External audit scheduled
- [ ] Bug bounty program planned

## 📁 Project Structure

```
fund-ur-memory-contract/
├── src/
│   ├── FUMVault.sol              # Main vault contract
│   ├── FUMVaultCore.sol          # Core functionality
│   ├── modules/
│   │   ├── ChainlinkPriceFeedModule.sol
│   │   ├── ChainlinkAutomationModule.sol
│   │   └── ChainlinkCCIPModule.sol
│   ├── interfaces/
│   │   └── IFUMVaultComplete.sol
│   ├── MockPriceFeed.sol         # Testing utilities
│   └── MockTokens.sol
├── script/
│   └── DeployFUMVault.s.sol      # Deployment script
├── test/
│   └── FUMVaultComplete.t.sol    # Comprehensive tests
├── docs/
│   └── FUM_VAULT_COMPLETE_DOCUMENTATION.md
└── foundry.toml                  # Foundry configuration
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Development Setup

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- **Documentation**: [Full Documentation](docs/FUM_VAULT_COMPLETE_DOCUMENTATION.md)
- **Website**: [fumvault.com](https://fumvault.com)
- **Discord**: [Join our community](https://discord.gg/fumvault)
- **Twitter**: [@FUMVault](https://twitter.com/FUMVault)

## 🙏 Acknowledgments

- [Chainlink](https://chain.link/) for providing reliable oracle infrastructure
- [OpenZeppelin](https://openzeppelin.com/) for secure smart contract libraries
- [Foundry](https://getfoundry.sh/) for the excellent development toolkit

## ⚠️ Disclaimer

This software is experimental and provided "as is". Use at your own risk. Always do your own research and consider the risks before using any DeFi protocol.

---

**Built with ❤️ by the F.U.M Protocol Team**
