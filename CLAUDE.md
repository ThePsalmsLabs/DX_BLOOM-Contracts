# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

### Building and Testing
```bash
# Build contracts
forge build

# Run all tests
forge test

# Run specific test file
forge test --match-path test/unit/CommerceProtocolIntegration.t.sol

# Run tests with gas reports
forge test --gas-report

# Format code
forge fmt

# Generate gas snapshots
forge snapshot
```

### Deployment Commands
```bash
# Deploy to Base Sepolia (testnet)
forge script script/Deploy.s.sol:Deploy --rpc-url base_sepolia --private-key <key> --broadcast --verify

# Deploy to Base Mainnet
forge script script/Deploy.s.sol:Deploy --rpc-url base_mainnet --private-key <key> --broadcast --verify

# Deploy to Celo Alfajores (testnet)
forge script script/Deploy.s.sol:Deploy --rpc-url celo_alfajores --private-key <key> --broadcast --verify

# Deploy to Celo Mainnet
forge script script/Deploy.s.sol:Deploy --rpc-url celo_mainnet --private-key <key> --broadcast --verify

# Register operator after deployment
forge script script/RegisterOperator.s.sol:RegisterOperator --rpc-url <network> --private-key <key> --broadcast
```

### Contract Verification
```bash
# Verify contracts on Base mainnet (for backup deployments)
forge script script/VerifyBaseMainnet.sol:VerifyBaseMainnet --rpc-url base_mainnet --broadcast

# Verify contracts on Celo networks
forge script script/VerifyCelo.sol:VerifyCelo --rpc-url celo_mainnet --broadcast
forge script script/VerifyCelo.sol:VerifyCelo --rpc-url celo_alfajores --broadcast

# Analyze constructor arguments for existing deployments
forge script script/AnalyzeConstructorArgs.sol:AnalyzeConstructorArgs --rpc-url base_mainnet
```

## Architecture Overview

This is a modular Solidity platform for onchain content subscriptions and payments built using Foundry. The system is split into specialized contracts for better gas optimization and maintainability.

### Core Contract Architecture

**Main Integration Contract:**
- `CommerceProtocolIntegration.sol` - Central hub that coordinates all platform functionality through manager contracts

**Registry Contracts:**
- `CreatorRegistry.sol` - Manages creator profiles and settings
- `ContentRegistry.sol` - Handles content metadata and access control

**Payment Contracts:**
- `PayPerView.sol` - Individual content purchases
- `SubscriptionManager.sol` - Recurring subscription payments
- `PriceOracle.sol` - Token price feeds and conversion rates

**Manager Contracts (Size Optimization):**
- `AdminManager.sol` - Administrative functions
- `ViewManager.sol` - Read-only view functions
- `AccessManager.sol` - Access control and permissions
- `SignatureManager.sol` - Signature validation
- `RefundManager.sol` - Payment refunds
- `PermitPaymentManager.sol` - EIP-2612 permit-based payments

### Shared Infrastructure

**Interfaces:**
- `ISharedTypes.sol` - Central type definitions to prevent enum conversion errors
- `IPlatformInterfaces.sol` - External protocol interfaces

**Libraries:**
- `PaymentUtilsLib.sol` - Payment calculation utilities
- `PaymentValidatorLib.sol` - Payment validation logic
- `PermitHandlerLib.sol` - EIP-2612 permit handling

### Network Configuration

The platform supports:
- **Base Mainnet** (Chain ID: 8453)
- **Base Sepolia** (Chain ID: 84532)
- **Celo Mainnet** (Chain ID: 42220)
- **Celo Alfajores** (Chain ID: 44787)

RPC endpoints and block explorer API keys are configured in `foundry.toml` using environment variables.

#### Required Environment Variables

**Base Networks:**
- `BASESCAN_API_KEY` - API key for Basescan verification
- `MAINNET_FEE_RECIPIENT` - Production fee recipient for Base Mainnet
- `MAINNET_OPERATOR_SIGNER` - Production operator signer for Base Mainnet
- `TESTNET_FEE_RECIPIENT` - Test fee recipient for Base Sepolia (optional, defaults to deployer)
- `TESTNET_OPERATOR_SIGNER` - Test operator signer for Base Sepolia (optional, defaults to deployer)

**Celo Networks:**
- `CELOSCAN_API_KEY` - API key for Celoscan verification
- `CELO_MAINNET_FEE_RECIPIENT` - Production fee recipient for Celo Mainnet
- `CELO_MAINNET_OPERATOR_SIGNER` - Production operator signer for Celo Mainnet
- `CELO_TESTNET_FEE_RECIPIENT` - Test fee recipient for Celo Alfajores (optional, defaults to deployer)
- `CELO_TESTNET_OPERATOR_SIGNER` - Test operator signer for Celo Alfajores (optional, defaults to deployer)

**Deployment:**
- `PRIVATE_KEY` - Private key for deployment (or use Foundry keystore with --account flag)

### Testing Structure

**Test Helpers:**
- `TestSetup.sol` - Base contract for all tests with common setup
- `TestConstants.sol` - Shared test constants
- `TestUtils.sol` - Testing utilities

**Test Categories:**
- `unit/` - Individual contract testing
- `integration/` - Cross-contract interaction tests
- `mocks/` - Mock contracts for testing (MockERC20, MockCommerceProtocol, etc.)

### Development Notes

- Uses Solidity 0.8.23 with optimizer enabled (20000 runs)
- Implements EIP-712 for signature validation
- Uses OpenZeppelin contracts for security primitives
- All shared types are centralized in `ISharedTypes.sol` to prevent type mismatches
- Contract size is optimized through manager pattern and libraries
- Fuzz testing configured with 1000 runs
- Invariant testing with 256 runs and depth 15

### Payment Flow Architecture

The system supports multiple payment types defined in `ISharedTypes.PaymentType`:
- PayPerView (0) - One-time content access
- Subscription (1) - Recurring access
- Tip (2) - Optional creator tips  
- Donation (3) - Direct creator support

Payment flows go through the main integration contract which delegates to appropriate specialized contracts and validates through the manager system.