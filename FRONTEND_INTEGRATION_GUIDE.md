# Cipher Frontend Integration Guide

Complete guide for frontend developers to integrate with the Cipher Protocol smart contract.

## Table of Contents
1. [Contract Overview](#contract-overview)
2. [Contract Address & ABI](#contract-address--abi)
3. [Core Data Types](#core-data-types)
4. [Essential Functions](#essential-functions)
5. [Events to Listen](#events-to-listen)
6. [Integration Examples](#integration-examples)
7. [Error Handling](#error-handling)
8. [Best Practices](#best-practices)

## Contract Overview

Cipher is a DeFi vault system that allows users to lock assets with time and/or price conditions. Users can create vaults that unlock when:
- **Time condition**: After a specific timestamp
- **Price condition**: When token price reaches target
- **Combined conditions**: Time OR Price, or Time AND Price

### Key Features
- **Automated unlocking** via Chainlink Automation
- **Emergency withdrawal** with 10% penalty
- **Multi-token support** (ETH, ERC20 tokens)
- **Real-time price feeds** via Chainlink

## Contract Address & ABI

### Avalanche Fuji Testnet
```javascript
const CONTRACT_ADDRESS = "0x5274A2153cF842E3bD1D4996E01d567750d0e739";
const CHAIN_ID = 43113; // Avalanche Fuji
```

> Explorer link: https://testnet.snowtrace.io/address/0x5274A2153cF842E3bD1D4996E01d567750d0e739

### ABI Location
```bash
# After compilation, ABI is available at:
./out/FUMVault.sol/FUMVault.json
```

## Core Data Types

### Enums
```typescript
enum ConditionType {
  TIME_ONLY = 0,
  PRICE_ONLY = 1,
  TIME_OR_PRICE = 2,
  TIME_AND_PRICE = 3
}

enum VaultStatus {
  ACTIVE = 0,
  UNLOCKED = 1,
  WITHDRAWN = 2,
  EMERGENCY = 3
}
```

### Vault Structure
```typescript
interface Vault {
  owner: string;           // Vault owner address
  token: string;           // Token address (0x0 for ETH)
  amount: bigint;          // Amount locked (in wei)
  unlockTime: bigint;      // Unix timestamp for unlock
  targetPrice: bigint;     // Target price in USD (8 decimals)
  conditionType: ConditionType;
  status: VaultStatus;
  createdAt: bigint;       // Creation timestamp
  emergencyInitiated: bigint; // Emergency timestamp
}
```

### Emergency Penalty Structure
```typescript
interface EmergencyPenalty {
  amount: bigint;          // Penalty amount
  penaltyTime: bigint;     // When penalty was created
  claimed: boolean;        // Whether penalty was claimed
}
```

## Essential Functions

### 1. Vault Creation Functions

#### Create Time-Only Vault
```typescript
// Unlock after specific time
async function createTimeVault(
  token: string,      // address(0) for ETH
  amount: bigint,     // Amount in wei
  unlockTime: bigint  // Unix timestamp
): Promise<bigint> { // Returns vault ID
  const tx = await contract.createTimeVault(token, amount, unlockTime, {
    value: token === "0x0000000000000000000000000000000000000000" ? amount : 0
  });
  const receipt = await tx.wait();
  return getVaultIdFromReceipt(receipt);
}
```

#### Create Price-Only Vault
```typescript
// Unlock when price reaches target
async function createPriceVault(
  token: string,       // Token address
  amount: bigint,      // Amount in wei
  targetPrice: bigint  // Price in USD (8 decimals)
): Promise<bigint> {
  const tx = await contract.createPriceVault(token, amount, targetPrice, {
    value: token === "0x0000000000000000000000000000000000000000" ? amount : 0
  });
  const receipt = await tx.wait();
  return getVaultIdFromReceipt(receipt);
}
```

#### Create Combined Condition Vaults
```typescript
// Time OR Price (unlocks when either condition is met)
async function createTimeOrPriceVault(
  token: string,
  amount: bigint,
  unlockTime: bigint,
  targetPrice: bigint
): Promise<bigint> {
  const tx = await contract.createTimeOrPriceVault(token, amount, unlockTime, targetPrice, {
    value: token === "0x0000000000000000000000000000000000000000" ? amount : 0
  });
  return getVaultIdFromReceipt(await tx.wait());
}

// Time AND Price (unlocks when both conditions are met)
async function createTimeAndPriceVault(
  token: string,
  amount: bigint,
  unlockTime: bigint,
  targetPrice: bigint
): Promise<bigint> {
  const tx = await contract.createTimeAndPriceVault(token, amount, unlockTime, targetPrice, {
    value: token === "0x0000000000000000000000000000000000000000" ? amount : 0
  });
  return getVaultIdFromReceipt(await tx.wait());
}
```

### 2. Vault Operations

#### Withdraw from Unlocked Vault
```typescript
async function withdrawVault(vaultId: bigint): Promise<void> {
  const tx = await contract.withdrawVault(vaultId);
  await tx.wait();
}
```

#### Emergency Withdrawal
```typescript
async function emergencyWithdraw(vaultId: bigint): Promise<void> {
  const tx = await contract.executeEmergencyWithdrawal(vaultId);
  await tx.wait();
}
```

#### Claim Emergency Penalty
```typescript
async function claimPenalty(): Promise<void> {
  const tx = await contract.claimEmergencyPenalty();
  await tx.wait();
}
```

### 3. View Functions

#### Get Vault Information
```typescript
async function getVault(vaultId: bigint): Promise<Vault> {
  return await contract.getVault(vaultId);
}
```

#### Get User's Vaults
```typescript
async function getUserVaults(userAddress: string): Promise<bigint[]> {
  return await contract.getOwnerVaults(userAddress);
}
```

#### Check Vault Conditions
```typescript
async function checkConditions(vaultId: bigint): Promise<boolean> {
  return await contract.checkConditions(vaultId);
}
```

#### Get Current Price
```typescript
async function getCurrentPrice(token: string): Promise<bigint> {
  return await contract.getCurrentPrice(token);
}
```

#### Get Contract Stats
```typescript
async function getContractStats(): Promise<{totalVaults: bigint, contractBalance: bigint}> {
  const [totalVaults, contractBalance] = await contract.getContractStats();
  return { totalVaults, contractBalance };
}
```

#### Get Emergency Penalty Info
```typescript
async function getEmergencyPenalty(userAddress: string): Promise<EmergencyPenalty> {
  return await contract.getEmergencyPenalty(userAddress);
}
```

## Events to Listen

### Key Events for Frontend
```typescript
// Vault created
contract.on("VaultCreated", (vaultId, owner, token, amount, conditionType, unlockTime, targetPrice) => {
  console.log(`Vault ${vaultId} created by ${owner}`);
});

// Vault unlocked (ready for withdrawal)
contract.on("VaultUnlocked", (vaultId, reason) => {
  console.log(`Vault ${vaultId} unlocked: ${reason}`);
});

// Vault withdrawn
contract.on("VaultWithdrawn", (vaultId, owner, amount) => {
  console.log(`Vault ${vaultId} withdrawn: ${amount} wei`);
});

// Emergency withdrawal
contract.on("EmergencyExecuted", (vaultId, owner, amount, penalty) => {
  console.log(`Emergency withdrawal: ${amount} wei, penalty: ${penalty} wei`);
});

// Penalty claimed
contract.on("PenaltyClaimed", (user, amount) => {
  console.log(`Penalty claimed by ${user}: ${amount} wei`);
});
```

## Integration Examples

### Complete Vault Creation Flow
```typescript
import { ethers } from 'ethers';

class FUMVaultIntegration {
  private contract: ethers.Contract;
  private signer: ethers.Signer;

  constructor(contractAddress: string, abi: any, signer: ethers.Signer) {
    this.contract = new ethers.Contract(contractAddress, abi, signer);
    this.signer = signer;
  }

  // Create a time vault with ETH
  async createETHTimeVault(amountETH: string, unlockTimeSeconds: number) {
    const amount = ethers.parseEther(amountETH);
    const unlockTime = BigInt(Math.floor(Date.now() / 1000) + unlockTimeSeconds);

    try {
      const tx = await this.contract.createTimeVault(
        "0x0000000000000000000000000000000000000000", // ETH
        amount,
        unlockTime,
        { value: amount }
      );

      const receipt = await tx.wait();
      const vaultId = this.getVaultIdFromReceipt(receipt);

      return {
        success: true,
        vaultId,
        txHash: receipt.hash
      };
    } catch (error) {
      return {
        success: false,
        error: error.message
      };
    }
  }

  // Get vault status with human-readable info
  async getVaultStatus(vaultId: bigint) {
    try {
      const vault = await this.contract.getVault(vaultId);
      const conditionsMet = await this.contract.checkConditions(vaultId);

      return {
        vault,
        conditionsMet,
        canWithdraw: vault.status === 1, // UNLOCKED
        timeRemaining: vault.unlockTime > 0 ?
          Math.max(0, Number(vault.unlockTime) - Math.floor(Date.now() / 1000)) : 0,
        formattedAmount: ethers.formatEther(vault.amount)
      };
    } catch (error) {
      throw new Error(`Failed to get vault status: ${error.message}`);
    }
  }

  private getVaultIdFromReceipt(receipt: any): bigint {
    const vaultCreatedEvent = receipt.logs.find(
      (log: any) => log.topics[0] === ethers.id("VaultCreated(uint256,address,address,uint256,uint8,uint256,uint256)")
    );
    return BigInt(vaultCreatedEvent.topics[1]);
  }
}
```

### Real-time Vault Monitoring
```typescript
class VaultMonitor {
  private contract: ethers.Contract;
  private userAddress: string;

  constructor(contract: ethers.Contract, userAddress: string) {
    this.contract = contract;
    this.userAddress = userAddress;
  }

  // Monitor user's vaults and check for unlock conditions
  async monitorUserVaults() {
    const vaultIds = await this.contract.getOwnerVaults(this.userAddress);
    const vaultStatuses = [];

    for (const vaultId of vaultIds) {
      const vault = await this.contract.getVault(vaultId);
      const conditionsMet = await this.contract.checkConditions(vaultId);

      vaultStatuses.push({
        id: vaultId,
        status: this.getStatusString(vault.status),
        canWithdraw: vault.status === 1,
        conditionsMet,
        amount: ethers.formatEther(vault.amount),
        token: vault.token === "0x0000000000000000000000000000000000000000" ? "ETH" : vault.token,
        unlockTime: vault.unlockTime > 0 ? new Date(Number(vault.unlockTime) * 1000) : null,
        targetPrice: vault.targetPrice > 0 ? Number(vault.targetPrice) / 1e8 : null
      });
    }

    return vaultStatuses;
  }

  private getStatusString(status: number): string {
    const statuses = ["ACTIVE", "UNLOCKED", "WITHDRAWN", "EMERGENCY"];
    return statuses[status] || "UNKNOWN";
  }

  // Set up event listeners for real-time updates
  setupEventListeners(callback: (event: any) => void) {
    // Listen for vault unlocks
    this.contract.on("VaultUnlocked", (vaultId, reason) => {
      callback({
        type: "VAULT_UNLOCKED",
        vaultId: vaultId.toString(),
        reason
      });
    });

    // Listen for withdrawals
    this.contract.on("VaultWithdrawn", (vaultId, owner, amount) => {
      if (owner.toLowerCase() === this.userAddress.toLowerCase()) {
        callback({
          type: "VAULT_WITHDRAWN",
          vaultId: vaultId.toString(),
          amount: ethers.formatEther(amount)
        });
      }
    });
  }
}
```

## Error Handling

### Common Errors and Solutions
```typescript
const ERROR_CODES = {
  // Vault creation errors
  "InsufficientAmount": "Amount too small (minimum 0.001 ETH)",
  "InvalidTimeCondition": "Unlock time must be in the future",
  "InvalidPriceCondition": "Target price must be greater than 0",
  "TokenNotSupported": "Token is not supported by the contract",
  "PriceFeedNotSet": "Price feed not configured for this token",

  // Vault operation errors
  "VaultNotFound": "Vault does not exist",
  "VaultNotActive": "Vault is not in active state",
  "VaultNotUnlocked": "Vault conditions not met yet",
  "NotVaultOwner": "Only vault owner can perform this action",
  "ConditionsNotMet": "Vault unlock conditions not satisfied",

  // Emergency withdrawal errors
  "EmergencyAlreadyInitiated": "Emergency withdrawal already in progress",
  "PenaltyNotClaimable": "Penalty claim period not reached (3 months)",
  "NoPenaltyToClaim": "No penalty available to claim"
};

function handleContractError(error: any): string {
  const errorMessage = error.message || error.toString();

  // Check for known error codes
  for (const [code, message] of Object.entries(ERROR_CODES)) {
    if (errorMessage.includes(code)) {
      return message;
    }
  }

  // Handle common transaction errors
  if (errorMessage.includes("insufficient funds")) {
    return "Insufficient funds for transaction";
  }
  if (errorMessage.includes("user rejected")) {
    return "Transaction cancelled by user";
  }
  if (errorMessage.includes("gas")) {
    return "Transaction failed due to gas issues";
  }

  return "Transaction failed. Please try again.";
}
```

## Best Practices

### 1. Gas Optimization
```typescript
// Batch multiple vault operations
async function batchWithdrawVaults(vaultIds: bigint[]) {
  const promises = vaultIds.map(id => contract.withdrawVault(id));
  return Promise.allSettled(promises);
}

// Use static calls to check conditions before transactions
async function canWithdrawVault(vaultId: bigint): Promise<boolean> {
  try {
    await contract.withdrawVault.staticCall(vaultId);
    return true;
  } catch {
    return false;
  }
}
```

### 2. Price Formatting
```typescript
// Format prices consistently (Chainlink uses 8 decimals)
function formatPrice(price: bigint): string {
  return (Number(price) / 1e8).toFixed(2);
}

// Parse user input to contract format
function parsePrice(priceString: string): bigint {
  return BigInt(Math.floor(parseFloat(priceString) * 1e8));
}
```

### 3. Time Handling
```typescript
// Convert user-friendly time to timestamp
function getUnlockTimestamp(days: number, hours: number = 0): bigint {
  const now = Math.floor(Date.now() / 1000);
  const seconds = (days * 24 * 60 * 60) + (hours * 60 * 60);
  return BigInt(now + seconds);
}

// Format timestamp for display
function formatUnlockTime(timestamp: bigint): string {
  if (timestamp === 0n) return "No time condition";
  const date = new Date(Number(timestamp) * 1000);
  return date.toLocaleString();
}
```

### 4. Transaction Monitoring
```typescript
async function waitForTransaction(txHash: string, maxWaitTime: number = 60000) {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const startTime = Date.now();

  while (Date.now() - startTime < maxWaitTime) {
    const receipt = await provider.getTransactionReceipt(txHash);
    if (receipt) {
      return receipt;
    }
    await new Promise(resolve => setTimeout(resolve, 2000));
  }

  throw new Error("Transaction timeout");
}
```

## Constants Reference

```typescript
const CONSTANTS = {
  EMERGENCY_PENALTY: 1000,        // 10% (basis points)
  PENALTY_CLAIM_DELAY: 7776000,   // 90 days in seconds
  BASIS_POINTS: 10000,
  MIN_VAULT_AMOUNT: "1000000000000000", // 0.001 ETH in wei

  // Supported tokens on Avalanche Fuji
  TOKENS: {
    ETH: "0x0000000000000000000000000000000000000000",
    WAVAX: "0xd00ae08403B9bbb9124bB305C09058E32C39A48c"
  },

  // Price feed addresses
  PRICE_FEEDS: {
    ETH_USD: "0x86d67c3D38D2bCeE722E601025C25a575021c6EA",
    AVAX_USD: "0x5498BB86BC934c8D34FDA08E81D444153d0D06aD"
  }
};
```

## Testing Integration

```typescript
// Test contract connection
async function testConnection(contract: ethers.Contract): Promise<boolean> {
  try {
    const stats = await contract.getContractStats();
    console.log("Contract connected successfully", stats);
    return true;
  } catch (error) {
    console.error("Contract connection failed:", error);
    return false;
  }
}

// Test vault creation (on testnet)
async function testVaultCreation(contract: ethers.Contract) {
  const amount = ethers.parseEther("0.01"); // 0.01 ETH
  const unlockTime = BigInt(Math.floor(Date.now() / 1000) + 3600); // 1 hour

  try {
    const tx = await contract.createTimeVault(
      "0x0000000000000000000000000000000000000000",
      amount,
      unlockTime,
      { value: amount }
    );

    console.log("Test vault created:", tx.hash);
    return await tx.wait();
  } catch (error) {
    console.error("Test vault creation failed:", error);
    throw error;
  }
}
```

## Quick Start Checklist

1. **Setup Contract Connection**
   - [ ] Add contract address and ABI to your project
   - [ ] Initialize ethers.js with provider and signer
   - [ ] Test connection with `getContractStats()`

2. **Implement Core Functions**
   - [ ] Vault creation (time, price, combined)
   - [ ] Vault monitoring and status checking
   - [ ] Withdrawal functionality
   - [ ] Emergency operations

3. **Add Event Listeners**
   - [ ] VaultCreated events
   - [ ] VaultUnlocked events
   - [ ] VaultWithdrawn events
   - [ ] EmergencyExecuted events

4. **Error Handling**
   - [ ] Implement error code mapping
   - [ ] Add user-friendly error messages
   - [ ] Handle transaction failures gracefully

5. **Testing**
   - [ ] Test on Avalanche Fuji testnet
   - [ ] Verify all vault types work correctly
   - [ ] Test emergency withdrawal flow
   - [ ] Validate event listening

This comprehensive guide provides everything needed to integrate F.U.M into your frontend application. For additional support, refer to the contract source code and test files.