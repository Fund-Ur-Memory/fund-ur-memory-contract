# F.U.M Vault - Fund Ur Memory

> **DeFi commitment contracts for automated asset management with time and price conditions**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)
[![Chainlink](https://img.shields.io/badge/Powered%20by-Chainlink-375BD2.svg)](https://chain.link/)

F.U.M Vault is a DeFi protocol that allows users to lock assets with customizable time and price conditions. The protocol uses Chainlink price feeds and automation to automatically unlock vaults when conditions are met, helping users implement disciplined investment strategies.

## Key Features

- **Time-based Vaults**: Lock assets until a specific timestamp
- **Price-based Vaults**: Unlock when token price reaches target
- **Combined Conditions**: Time OR Price, or Time AND Price logic
- **Chainlink Integration**: Real-time price feeds and automation
- **Emergency Withdrawals**: Immediate access with 10% penalty
- **Multi-token Support**: ETH and ERC20 tokens
- **Automated Unlocking**: Chainlink Automation monitors conditions 24/7
- **Security**: ReentrancyGuard, access controls, comprehensive testing

## Architecture

The F.U.M protocol consists of a single main contract with modular functionality:

- **FUMVault.sol**: Main contract handling vault creation, management, and withdrawals
- **Chainlink Integration**: Price feeds and automation for condition monitoring
- **Emergency System**: Penalty-based emergency withdrawal mechanism

## Quick Start

### Prerequisites

- [Foundry](https://getfoundry.sh/) installed
- Node.js 16+ for frontend
- Git

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd fund-ur-memory-contract

# Install dependencies
forge install

# Set up environment variables
export PRIVATE_KEY="your_private_key_here"
export FUJI_RPC_URL="https://api.avax-test.network/ext/bc/C/rpc"
export FUM_VAULT_ADDRESS="0x5274A2153cF842E3bD1D4996E01d567750d0e739"
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

**Test Coverage:**
- Vault creation (time, price, combined conditions)
- Condition checking and automated unlocking
- Withdrawal operations and emergency system
- Chainlink automation integration
- Price feed validation and error handling
- Access control and security measures

### Deploy

```bash
# Deploy to Avalanche Fuji testnet
forge script script/DeployFUM.s.sol --rpc-url $FUJI_RPC_URL --broadcast

# Setup contract configuration
forge script script/SetupFUM.s.sol --rpc-url $FUJI_RPC_URL --broadcast

# Test deployment
forge script script/QuickTest.s.sol --rpc-url $FUJI_RPC_URL
```

## Usage Examples

### Create a Time-based Vault

```bash
# Create vault that unlocks in 1 hour
forge script script/ManageVaults.s.sol:CreateVaults --rpc-url $FUJI_RPC_URL --broadcast
```

```solidity
// Lock 0.1 ETH for 1 hour
uint256 vaultId = fumVault.createTimeVault{value: 0.1 ether}(
    address(0), // ETH
    0.1 ether,
    block.timestamp + 1 hours
);
```

### Create a Price-based Vault

```solidity
// Lock ETH until it reaches $4000
uint256 vaultId = fumVault.createPriceVault{value: 0.1 ether}(
    address(0), // ETH
    0.1 ether,
    400000000000 // $4000 target (8 decimals)
);
```

### Create a Combined Vault

```solidity
// Lock for 1 day OR until ETH hits $4000
uint256 vaultId = fumVault.createTimeOrPriceVault{value: 0.1 ether}(
    address(0), // ETH
    0.1 ether,
    block.timestamp + 1 days,
    400000000000 // $4000 target
);
```

## Chainlink Integration

### Price Feeds
- Real-time price data from Chainlink oracles
- Support for ETH/USD, AVAX/USD, BTC/USD on Avalanche Fuji
- Built-in staleness validation
- 8-decimal precision pricing

### Automation
- Automated vault condition monitoring
- 5-second check intervals for fast response
- Batch processing for gas efficiency
- Automatic vault unlocking when conditions are met

**Supported Price Feeds (Avalanche Fuji):**
- ETH/USD: `0x86d67c3D38D2bCeE722E601025C25a575021c6EA`
- AVAX/USD: `0x5498BB86BC934c8D34FDA08E81D444153d0D06aD`
- BTC/USD: `0x31CF013A08c6Ac228C94551d535d5BAfE19c602a`

## Supported Networks

| Network | Chain ID | Status | Contract Address |
|---------|----------|--------|------------------|
| Avalanche Fuji (Testnet) | 43113 | ✅ Deployed | `0x5274A2153cF842E3bD1D4996E01d567750d0e739` |

**Current Deployment:**
- **Network**: Avalanche Fuji Testnet
- **Contract**: `0x5274A2153cF842E3bD1D4996E01d567750d0e739`
- **Explorer**: [View on Snowtrace](https://testnet.snowtrace.io/address/0x5274A2153cF842E3bD1D4996E01d567750d0e739)

## Testing

The project includes comprehensive tests covering:

- Vault creation with different condition types
- Time-based and price-based unlocking
- Emergency withdrawal system with penalties
- Price feed validation and staleness checks
- Chainlink automation integration
- Access control and security measures
- Error conditions and edge cases

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-contract FUMVaultTest

# Run with verbosity for debugging
forge test -vvv

# Generate coverage report
forge coverage --report lcov
```

## Security

### Security Measures
- **ReentrancyGuard**: Protection against reentrancy attacks
- **Access Control**: Owner-based permissions with proper validation
- **Input Validation**: Comprehensive parameter checking
- **Price Feed Validation**: Staleness and sanity checks
- **Emergency System**: 10% penalty for immediate withdrawals
- **Pausable**: Contract can be paused in emergencies

### Security Status
- Internal security review: In progress
- External audit: Planned for production deployment
- Testnet deployment: Active for testing

## Project Structure

```
fund-ur-memory-contract/
├── src/
│   ├── FUMVault.sol              # Main vault contract
│   └── interfaces/
│       └── IFUMVault.sol         # Contract interface
├── script/                       # Essential scripts only
│   ├── DeployFUM.s.sol          # Deployment script
│   ├── SetupFUM.s.sol           # Configuration script
│   ├── ManageVaults.s.sol       # Vault management
│   ├── ViewUnlockedVaults.s.sol # Monitoring script
│   ├── ClaimUnlockedVaults.s.sol # Claiming script
│   ├── EmergencyOperations.s.sol # Emergency functions
│   ├── MonitorAutomation.s.sol  # Automation monitoring
│   └── QuickTest.s.sol          # Basic testing
├── test/
│   └── FUMVault.t.sol           # Comprehensive tests
├── docs/
│   ├── FRONTEND_INTEGRATION_GUIDE.md
│   ├── ESSENTIAL_SCRIPTS.md
│   └── VAULT_MANAGEMENT_GUIDE.md
└── foundry.toml                 # Foundry configuration
```

## Available Scripts

### Essential Operations
```bash
# Deploy contract
forge script script/DeployFUM.s.sol --rpc-url $FUJI_RPC_URL --broadcast

# Setup configuration
forge script script/SetupFUM.s.sol --rpc-url $FUJI_RPC_URL --broadcast

# Create test vaults
forge script script/ManageVaults.s.sol:CreateVaults --rpc-url $FUJI_RPC_URL --broadcast

# Monitor vaults
forge script script/ViewUnlockedVaults.s.sol:ViewUnlockedVaults --rpc-url $FUJI_RPC_URL

# Claim ready vaults
forge script script/ClaimUnlockedVaults.s.sol:ClaimUnlockedVaults --rpc-url $FUJI_RPC_URL --broadcast

# Emergency withdrawal
VAULT_ID=1 forge script script/EmergencyOperations.s.sol:EmergencyWithdrawal --rpc-url $FUJI_RPC_URL --broadcast
```

## Documentation

- **[Frontend Integration Guide](docs/FRONTEND_INTEGRATION_GUIDE.md)** - Complete guide for frontend developers
- **[Essential Scripts](docs/ESSENTIAL_SCRIPTS.md)** - Overview of all available scripts
- **[Vault Management Guide](docs/VAULT_MANAGEMENT_GUIDE.md)** - Detailed vault operations

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass: `forge test`
5. Submit a pull request

## License

This project is licensed under the MIT License.

## Acknowledgments

- [Chainlink](https://chain.link/) for oracle infrastructure
- [OpenZeppelin](https://openzeppelin.com/) for security libraries
- [Foundry](https://getfoundry.sh/) for development tools
