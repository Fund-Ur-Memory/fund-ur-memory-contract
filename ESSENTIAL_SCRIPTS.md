# Essential Cipher Scripts

This document lists the essential scripts kept in the project after cleanup.

## Core Scripts (8 Essential Files)

### 1. **DeployCipher.s.sol**
- **Purpose**: Deploy Cipher contract to Avalanche Fuji
- **Usage**: `forge script script/DeployCipher.s.sol --rpc-url $FUJI_RPC_URL --broadcast`
- **Description**: Core deployment script that creates the CipherVault contract

### 2. **SetupCipher.s.sol**
- **Purpose**: Configure token support and price feeds
- **Usage**: `forge script script/SetupCipher.s.sol --rpc-url $FUJI_RPC_URL --broadcast`
- **Description**: Essential configuration script that sets up ETH/AVAX support and price feeds

### 3. **ManageVaults.s.sol**
- **Purpose**: Create test vaults (time, price, combined conditions)
- **Usage**: `forge script script/ManageVaults.s.sol:CreateVaults --rpc-url $FUJI_RPC_URL --broadcast`
- **Description**: Core vault management script for creating different types of vaults

### 4. **ViewUnlockedVaults.s.sol**
- **Purpose**: Monitor vault status and find unlocked vaults
- **Usage**: `forge script script/ViewUnlockedVaults.s.sol:ViewUnlockedVaults --rpc-url $FUJI_RPC_URL`
- **Description**: Essential monitoring script to check vault statuses

### 5. **ClaimUnlockedVaults.s.sol**
- **Purpose**: Automatically claim ready vaults
- **Usage**: `forge script script/ClaimUnlockedVaults.s.sol:ClaimUnlockedVaults --rpc-url $FUJI_RPC_URL --broadcast`
- **Description**: Essential claiming script for withdrawing from unlocked vaults

### 6. **EmergencyOperations.s.sol**
- **Purpose**: Emergency withdrawal and penalty management
- **Usage**: 
  - Emergency withdraw: `VAULT_ID=1 forge script script/EmergencyOperations.s.sol:EmergencyWithdrawal --rpc-url $FUJI_RPC_URL --broadcast`
  - Check penalty: `forge script script/EmergencyOperations.s.sol:CheckEmergencyPenalty --rpc-url $FUJI_RPC_URL`
- **Description**: Essential emergency functions for urgent vault access

### 7. **MonitorAutomation.s.sol**
- **Purpose**: Monitor Chainlink automation status
- **Usage**: `forge script script/MonitorAutomation.s.sol:MonitorAutomation --rpc-url $FUJI_RPC_URL`
- **Description**: Essential automation monitoring for Chainlink integration

### 8. **QuickTest.s.sol**
- **Purpose**: Quick contract functionality test
- **Usage**: `forge script script/QuickTest.s.sol:QuickTest --rpc-url $FUJI_RPC_URL`
- **Description**: Essential testing script to verify contract accessibility

## Typical Workflow

### Daily Operations:
```bash
# 1. Check vault status
forge script script/ViewUnlockedVaults.s.sol:ViewUserVaults --rpc-url $FUJI_RPC_URL

# 2. Claim ready vaults
forge script script/ClaimUnlockedVaults.s.sol:ClaimUnlockedVaults --rpc-url $FUJI_RPC_URL --broadcast

# 3. Monitor automation
forge script script/MonitorAutomation.s.sol:MonitorAutomation --rpc-url $FUJI_RPC_URL
```

### Initial Setup:
```bash
# 1. Deploy contract
forge script script/DeployFUM.s.sol --rpc-url $FUJI_RPC_URL --broadcast

# 2. Configure contract
export FUM_VAULT_ADDRESS=<deployed_address>
forge script script/SetupFUM.s.sol --rpc-url $FUJI_RPC_URL --broadcast

# 3. Test functionality
forge script script/QuickTest.s.sol:QuickTest --rpc-url $FUJI_RPC_URL

# 4. Create test vaults
forge script script/ManageVaults.s.sol:CreateVaults --rpc-url $FUJI_RPC_URL --broadcast
```

## Benefits of Cleanup

- **Reduced complexity**: From 18 scripts to 8 essential scripts
- **Cleaner codebase**: Removed experimental and redundant code
- **Faster compilation**: Fewer files to compile
- **Better maintainability**: Focus on core functionality
- **Clear purpose**: Each remaining script has a specific, essential role
