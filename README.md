# SUI Wallet MCP Server

A **multi-tenant, non-custodial SUI wallet canister** that functions as an MCP server on the Internet Computer. Each IC principal (user or canister) automatically gets their own unique, secure SUI wallet derived from their Principal ID using threshold ECDSA.

## 🌟 Features

- **✅ Multi-Tenant Architecture**: Each IC principal automatically gets their own unique SUI wallet
- **✅ Non-Custodial**: Uses IC's threshold ECDSA for decentralized key management
- **✅ Deterministic Key Derivation**: Your SUI address is always derived from your IC identity
- **✅ Fully Functional Transfers**: Production-ready and tested on SUI mainnet
- **✅ Blake2b-256 Hashing**: Proper SUI signature scheme implementation
- **✅ MCP Tools**: Three working tools (address, balance, transfer)
- **✅ Secure by Design**: No private keys stored; all signing done via IC consensus

## 🚀 Live Demo

**Canister ID**: `jtr3i-2qaaa-aaaai-q34oq-cai` (IC Mainnet)

**Status**: ✅ Production-ready and fully operational on SUI mainnet

Try it live with the MCP Inspector or integrate it into your AI agent!

## Prerequisites

Before you begin, make sure you have the following tools installed on your system:

1.  **DFX:** The DFINITY Canister SDK. [Installation Guide](https://internetcomputer.org/docs/current/developer-docs/setup/install/).
2.  **Node.js:** Version 18.0 or higher. [Download](https://nodejs.org/).
3.  **MOPS:** The Motoko Package Manager. [Installation Guide](https://mops.one/docs/install).
4.  **Git:** The version control system. [Download](https://git-scm.com/).

---

## Part 1: Quick Start (Local Development)

This section guides you from zero to a working, testable MCP server on your local machine.

### Step 1: Initialize Your Repository

The Prometheus publishing process is tied to your Git history. Initialize a repository and make your first commit now.

```bash
git init
git add .
git commit -m "Initial commit from template"
```

### Step 2: Install Dependencies

This command will install both the required Node.js packages and the Motoko packages.

```bash
npm install
npm run mops:install
```

### Step 3: Deploy Your Server Locally

1.  **Start the Local Replica:** (Skip this if it's already running)
    ```bash
    npm run start
    ```
2.  **Deploy to the Local Replica:** (In a new terminal window)
    ```bash
    npm run deploy
    ```

### Step 4: Create an API Key

Since authentication is enabled for wallet security, you need an API key:

```bash
# Replace <your_canister_id> with your actual canister ID
dfx canister call <your_canister_id> create_my_api_key '("My SUI Wallet Key", vec { "openid" })'
```

**Save the returned API key!** This is the only time it will be shown.

### Step 5: Test with the MCP Inspector

Your SUI wallet server is now live with three tools available.

1.  **Launch the Inspector:**
    ```bash
    npm run inspector
    ```
2.  **Connect to Your Canister:** Use the local canister ID endpoint provided in the `npm run deploy` output.
    ```
    # Replace `your_canister_id` with the actual ID from the deploy output
    http://127.0.0.1:4943/mcp/?canisterId=your_canister_id
    ```
3.  **Add Authentication:** In the MCP Inspector, add your API key in the Authorization section using the `x-api-key` header.

4.  **Try the Tools:**
    - Call `wallet_get_address` to get your unique SUI address
    - Fund your address with SUI from an exchange or another wallet
    - Call `wallet_get_balance` to check your balance

🎉 **Congratulations!** You have a working multi-tenant SUI wallet!

---

## Part 2: Available Tools

### 1. `wallet_get_address`

Retrieves your unique SUI address derived from your IC Principal.

**Input**: None required

**Output**:
```json
{
  "address": "0x1234567890abcdef..."
}
```

**Example**:
```bash
# Using MCP Inspector - just call the tool with no parameters
# Your address will be deterministically derived from your authenticated principal
```

---

### 2. `wallet_get_balance`

Retrieves your current SUI balance in MIST (1 SUI = 1,000,000,000 MIST).

**Input**: None required

**Output**:
```json
{
  "balance": "1000000000"
}
```

**Note**: 
- Balance is returned as a string to handle large numbers
- 1 SUI = 1,000,000,000 MIST
- Queries SUI mainnet RPC at `https://fullnode.mainnet.sui.io:443`

**Example**:
```bash
# Using MCP Inspector
# 1. Authenticate with your API key
# 2. Call wallet_get_balance
# 3. Result shows your balance in MIST
```

---

### 3. `wallet_transfer`

**✅ FULLY FUNCTIONAL** - Transfers SUI from your wallet to another address.

**Input**:
```json
{
  "to_address": "0x...",
  "amount": "100000000",
  "gas_budget": "10000000"
}
```

**Output**:
```json
{
  "status": "success",
  "transaction_digest": "8Rf9k3..."
}
```

**Parameters**:
- `to_address`: Recipient's SUI address (must start with `0x`)
- `amount`: Amount in MIST to transfer (string)
- `gas_budget`: Gas budget in MIST (default: 10000000)

**How It Works**:
1. Queries your wallet for available coins
2. Builds transaction using `unsafe_transferSui` RPC method
3. Signs with your derived ECDSA key using:
   - Blake2b-256 hash of (intent + txBytes)
   - SHA256 intermediate hash
   - IC threshold ECDSA signing
   - Low-s signature normalization
4. Broadcasts signed transaction to SUI network
5. Returns transaction digest on success

**Example Successful Transfer**:
```bash
# Transfer 0.1 SUI (100,000,000 MIST) with 0.01 SUI gas budget
{
  "to_address": "0xabcdef1234567890...",
  "amount": "100000000",
  "gas_budget": "10000000"
}

# Response:
{
  "status": "success", 
  "transaction_digest": "8Rf9k3pQmN..."
}
```

**Requirements**:
- Your wallet must have sufficient SUI balance (amount + gas)
- Recipient address must be valid SUI address
- At least one coin object in your wallet

---

## Testing Multi-Tenancy

To test that each principal gets a unique wallet:

1. Create an API key for the first user and note their address
2. Create an API key for a second user (different principal)
3. Compare the addresses - they should be different
4. Each user can only access their own wallet via their API key

## Current Status

### ✅ Fully Operational
- **Multi-tenant architecture** with principal-based key derivation
- **Authentication** with API keys (Prometheus Protocol)
- **`wallet_get_address`** - Derives unique SUI address from IC Principal
- **`wallet_get_balance`** - Queries SUI testnet RPC for balance
- **`wallet_transfer`** - **WORKING!** Successfully transfers SUI on testnet
- **HTTP outcalls** with proper cycle provisioning (500M for transfers)
- **Public key caching** for performance optimization
- **ECDSA signing** with IC threshold signatures (10B cycles)
- **Blake2b-256 hashing** - Correct external hash for SUI
- **SHA256 intermediate hash** - Bridges Blake2b to IC's internal SHA256
- **Signature normalization** - Low-s requirement enforcement
- **Signature format** - Correct 0x01 flag for ECDSA Secp256k1

### 🎯 Technical Highlights

**Signature Pipeline** (Triple Hash):
```
1. Blake2b-256(intent [0,0,0] + txBytes) → 32 bytes
2. SHA256(blake2b_hash) → 32 bytes  
3. IC sign_with_ecdsa(sha256_hash) → 64 bytes (r||s)
4. Normalize signature (s ≤ N/2)
5. Construct: 0x01 + signature(64) + pubkey(33) = 98 bytes
```

**Key Derivation**:
```motoko
derivation_path = [[1], Principal.toBlob(caller)]
// Simple schema matching Rust standard implementation
```

**Tested & Verified**:
- ✅ Address derivation matches SUI standards
- ✅ Signatures pass SUI network validation
- ✅ **Transfers execute successfully on SUI mainnet**
- ✅ Multi-tenant isolation working correctly
- ✅ All three MCP tools fully functional

### 📊 Code Metrics
- **Total**: ~1,600 lines across 8 modular files
- **main.mo**: 524 lines (43% reduction from refactoring)
- **Modular architecture**: types, utils, crypto, wallet_tools, key_manager, sui_rpc, sui_tx
- **Clean separation**: RPC, crypto, and transaction logic isolated

---

## Part 4: Publish to the App Store (Deploy to Mainnet)

Instead of deploying to mainnet yourself, you publish your service to the Prometheus Protocol. The protocol then verifies, audits, and deploys your code for you.

### Step 1: Commit Your Changes

Make sure all your code changes (like enabling monetization) are committed to Git.

```bash
git add .
git commit -m "feat: enable monetization"
```

### Step 2: Publish Your Service

Use the `app-store` CLI to submit your service for verification and deployment.

```bash
# 1. Get your commit hash
git rev-parse HEAD
```

```bash
# 2. Run the init command to create your manifest
npm run app-store init 
```

Complete the prompts to set up your `prometheus.yml` manifest file.
Add your commit hash and the path to your WASM file (found in `.dfx/local/canisters/<your_canister_name>/<your_canister_name>.wasm`).

```bash
# 3. Run the publish command with your app version
npm run app-store publish "0.1.0"
```

Once your service passes the audit, the protocol will automatically deploy it and provide you with a mainnet canister ID. You can monitor the status on the **Prometheus Audit Hub**.

---

## Part 5: Managing Your Live Server

### Treasury Management

Your canister includes built-in Treasury functions to securely manage the funds it collects. You can call these with `dfx` against your **mainnet canister ID**.

-   `get_owner()`
-   `get_treasury_balance(ledger_id)`
-   `withdraw(ledger_id, amount, destination)`

### Updating Your Service (e.g., Enabling the Beacon)

Any code change to a live service requires publishing a new version.

1.  Open `src/main.mo` and uncomment the `beaconContext`.
2.  Commit the change: `git commit -m "feat: enable usage beacon"`.
3.  Re-run the **publishing process** from Part 3 with the new commit hash.

---

## 🏗️ Architecture

The wallet uses IC's native **threshold ECDSA** to derive a unique SUI wallet for each calling principal:

```
Your IC Principal → Derivation Path → ECDSA Public Key → SUI Address
```

Each user's signing capability is tied directly to their IC identity, ensuring maximum security without custodial risk.

### Key Derivation

## 🔒 How It Works

### Key Derivation

Each IC principal gets a unique, deterministic SUI wallet:

```
Your IC Principal → Derivation Path → IC ECDSA → Public Key → SUI Address
```

**Derivation Path**:
```motoko
derivation_path = [[1], Principal.toBlob(caller)]
// Schema V1 (single byte) + principal bytes
```

**Properties**:
- ✅ **Deterministic**: Same principal always gets the same SUI address
- ✅ **Isolated**: Different principals get completely different addresses
- ✅ **Secure**: Requires IC consensus to sign (threshold ECDSA)
- ✅ **Non-Custodial**: No private keys stored anywhere
- ✅ **Standard Compliant**: Matches Rust implementation patterns

### Signature Scheme

SUI requires a specific signature format. Here's our battle-tested pipeline:

**Step 1: Transaction Preparation**
```
Intent [0,0,0] + Transaction Bytes → Message to Sign
```

**Step 2: Triple Hash** (Critical for SUI compatibility)
```
1. Blake2b-256(message) → 32 bytes external hash
2. SHA256(blake2b_hash) → 32 bytes intermediate  
3. IC ECDSA signs SHA256 hash (internal SHA256 again)
```

**Why Triple Hash?**
- SUI requires Blake2b-256 for transaction hashing
- IC's threshold ECDSA does SHA256 internally
- We bridge with intermediate SHA256 (matching Rust implementation)

**Step 3: Signature Normalization**
```motoko
// SUI requires low-s signatures (s ≤ N/2)
if (s > N/2) {
  s' = N - s  // Normalize to low-s
}
```

**Step 4: Final Signature Construction**
```
0x01 (ECDSA Secp256k1 flag) + 
signature (64 bytes: r||s normalized) + 
compressed_pubkey (33 bytes)
= 98 bytes total
```

### Cycle Costs

- **ECDSA Public Key**: 10,000,000,000 cycles (10B)
- **ECDSA Signing**: 10,000,000,000 cycles (10B)
- **HTTP Outcalls**: 500,000,000 cycles (500M) for transfers
- **Public Key Caching**: Reduces repeated ECDSA calls

### RPC Configuration

**SUI Mainnet**: `https://fullnode.mainnet.sui.io:443`

**Methods Used**:
- `suix_getBalance`: Query wallet balance
- `suix_getCoins`: Get spendable coin objects
- `unsafe_transferSui`: Simple transfer (returns txBytes for signing)
- `sui_executeTransactionBlock`: Broadcast signed transaction

## 🏗️ Code Architecture

The codebase is organized into modular files for maximum maintainability and reusability:

### Core Modules

**`main.mo`** (524 lines)
- Main canister actor with MCP server setup
- Authentication and API key management
- HTTP request handling and routing
- Wallet context provider for tools

**`types.mo`** (17 lines)
- Shared type definitions
- `SuiCoin`: Coin object structure
- `SuiGasData`: Gas payment data

**`utils.mo`** (81 lines)
- `parseNat()`: Safe text to number parsing
- `encodeBase64/decodeBase64()`: Base64 encoding for RPC
- `hexEncode()`: Byte array to hex string conversion

**`crypto.mo`** (193 lines)
- `blake2bHash()`: Blake2b-256 with explicit 32-byte config
- `sha256Hash()`: SHA256 wrapper for intermediate hashing
- `publicKeyToSuiAddress()`: Converts pubkey to SUI address (Blake2b + bech32)
- `normalizeSignature()`: Low-s normalization (if s > N/2, compute s' = N - s)

**`key_manager.mo`** (105 lines)
- `getPublicKey()`: Derives 33-byte compressed secp256k1 key from IC ECDSA
- `signWithCallerKey()`: Signs message hash with IC ECDSA (10B cycles)
- `getDerivationPath()`: Builds derivation path `[[1], principal]`
- Public key caching with Map-based storage

**`sui_rpc.mo`** (286 lines)
- `querySuiBalance()`: Queries balance via SUI RPC
- `getSuiCoins()`: Fetches coin objects for spending
- `executeSuiTransaction()`: Broadcasts signed transactions
- RPC configuration and HTTP outcall management

**`sui_tx.mo`** (138 lines)
- `transferSuiSimple()`: Complete transfer flow
  1. Get txBytes from `unsafe_transferSui` RPC
  2. Construct intent message `[0,0,0] + txBytes`
  3. Blake2b-256 hash (32 bytes)
  4. SHA256 intermediate hash (32 bytes)
  5. IC sign_with_ecdsa (10B cycles)
  6. Normalize signature (low-s)
  7. Construct final: `0x01 + sig(64) + pubkey(33)`
  8. Execute transaction via RPC

**`wallet_tools.mo`** (173 lines)
- `walletGetAddressTool()`: Returns caller's unique SUI address
- `walletGetBalanceTool()`: Queries SUI balance via RPC
- `walletTransferTool()`: Constructs, signs, and broadcasts transfers
- Context-based dependency injection pattern

### Why This Architecture?

✅ **Separation of concerns** - Each module has a single responsibility  
✅ **Reusability** - Functions can be used independently  
✅ **Testability** - Easier to test individual components  
✅ **Maintainability** - Clean, focused code that's easy to understand  
✅ **Extensibility** - Easy to add new blockchains or features

---

---

## 🛣️ Roadmap

### ✅ Completed (v1.0)
- [x] Multi-tenant wallet architecture
- [x] Address derivation per principal (Blake2b-based)
- [x] Balance queries via SUI RPC
- [x] **Transaction signing and broadcasting** (Blake2b → SHA256 → IC ECDSA)
- [x] **Signature normalization** (low-s enforcement)
- [x] **Working transfers on SUI mainnet**
- [x] MCP tool implementations
- [x] Authentication with API keys
- [x] Modular code architecture

### 🔜 Future Enhancements (v2.0+)
- [ ] Intelligent coin selection (currently uses first available coin)
- [ ] Gas estimation and optimization
- [ ] Support for SUI Move calls (programmable transactions)
- [ ] Transaction history tracking
- [ ] Multi-coin transfers (batch operations)
- [ ] Support for SUI tokens (not just native SUI)
- [ ] NFT support

---

## 📖 Resources

-   [SPEC.md](./SPEC.md) - Detailed technical specification
-   [Prometheus Protocol Docs](https://prometheusprotocol.org/docs)
-   [SUI Documentation](https://docs.sui.io/)
-   [SUI Signatures Reference](https://docs.sui.io/concepts/cryptography/transaction-auth/signatures)
-   [IC Threshold ECDSA](https://internetcomputer.org/docs/current/developer-docs/integrations/t-ecdsa/)
-   [Blake2b Specification](https://www.blake2.net/)

## 🙏 Acknowledgments

This project was built with reference to:
- [SUI Rust SDK](https://github.com/MystenLabs/sui/tree/main/crates/sui-sdk) - Reference implementation for signature handling
- [Prometheus Protocol](https://prometheusprotocol.org/) - MCP server framework and app store
- Internet Computer community for threshold ECDSA support

## 📝 License

MIT License - see LICENSE file for details

---

## What's Next?

-   **Try It Live:** Test the wallet on IC mainnet with testnet SUI
-   **Contribute:** Submit PRs for coin selection, gas optimization, or new features
-   **Deploy Your Own:** Fork this repo and customize for your use case
-   **Learn More:** Check out the full [Service Developer Docs](https://prometheusprotocol.org/docs) for advanced topics
