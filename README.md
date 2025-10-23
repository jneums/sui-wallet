# SUI Wallet MCP Server

A **multi-tenant, non-custodial SUI wallet canister** that functions as an MCP server on the Internet Computer. This canister provides any principal (user or canister) with its own unique, secure SUI wallet, derived from its Principal ID.

## 🌟 Features

- **Multi-Tenant Architecture**: Each IC principal automatically gets their own unique SUI wallet
- **Non-Custodial**: Uses IC's threshold ECDSA for decentralized key management
- **Deterministic Key Derivation**: Your SUI address is always derived from your IC identity
- **Simple MCP Tools**: Abstract away blockchain complexity with easy-to-use tools
- **Secure by Design**: No private keys stored; all signing done via IC consensus

This guide assumes you are using `npm` as your package manager.

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
    - Fund your address with testnet SUI from [SUI Testnet Faucet](https://faucet.testnet.sui.io/)
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
  "address": "0x..."
}
```

### 2. `wallet_get_balance`

Retrieves your current SUI balance in MIST (1 SUI = 1,000,000,000 MIST).

**Input**: None required

**Output**:
```json
{
  "balance": "1000000000"
}
```

### 3. `wallet_transfer`

Transfers SUI from your wallet to another address.

**Input**:
```json
{
  "to_address": "0x...",
  "amount": "100000000"
}
```

**Output**:
```json
{
  "status": "success",
  "transaction_id": "..."
}
```

**Note**: Transfer functionality is currently a placeholder and will be fully implemented in the next iteration.

---

## Testing Multi-Tenancy

To test that each principal gets a unique wallet:

1. Create an API key for the first user and note their address
2. Create an API key for a second user (different principal)
3. Compare the addresses - they should be different
4. Each user can only access their own wallet via their API key

## Current Status

### ✅ Completed
- Multi-tenant architecture with principal-based key derivation
- Authentication with API keys
- `wallet_get_address` tool - fully functional
- `wallet_get_balance` tool - fully functional  
- HTTP outcalls with proper cycle provisioning
- Public key caching for performance
- Transaction signing infrastructure
- Basic transfer function structure

### 🚧 Known Limitations
- **Incomplete BCS Serialization**: Transaction commands are not fully serialized. The BCS encoding for complex programmable transactions needs completion.
- **Transfer Testing**: The `wallet_transfer` function is structurally complete but needs real testnet testing to verify transaction format.

### 🔜 To Complete Full Production Readiness
1. Implement complete BCS serialization for all transaction command types
2. Test transfers on SUI testnet with funded wallets
3. Add error handling for various SUI RPC edge cases
4. Implement coin selection strategy for optimal gas usage

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

The canister derives unique keys for each principal using:

```motoko
derivation_path = [CANISTER_SALT, Principal.toBlob(caller)]
```

This ensures:
- **Deterministic**: Same principal always gets the same SUI address
- **Isolated**: Different principals get different addresses
- **Secure**: Requires IC consensus to sign transactions

## 🏗️ Code Architecture

The codebase is organized into modular files for maintainability:

### Core Modules

- **`main.mo`**: Main canister actor with MCP server setup, authentication, and HTTP handling
- **`types.mo`**: Shared type definitions (SuiCoin, SuiGasData, etc.)
- **`utils.mo`**: Utility functions for parsing, encoding (base64, hex)
- **`crypto.mo`**: Cryptographic operations:
  - Public key to SUI address conversion (Blake2b-based)
  - ECDSA signature normalization (low-s requirement for SUI)
- **`wallet_tools.mo`**: MCP tool implementations:
  - `walletGetAddressTool`: Returns caller's unique SUI address
  - `walletGetBalanceTool`: Queries SUI balance via RPC
  - `walletTransferTool`: Constructs, signs, and broadcasts transactions

### Key Functions

```motoko
// In main.mo
getPublicKey(caller) -> derives 33-byte compressed secp256k1 key from IC ECDSA
getSuiAddress(caller) -> converts public key to SUI address
querySuiBalance(address) -> calls SUI RPC to get balance
getSuiCoins(address) -> fetches coin objects for spending
transferSuiSimple(...) -> creates and signs SUI transfer transaction
signWithCallerKey(...) -> signs message hash with IC ECDSA (10B cycles)

// In crypto.mo
publicKeyToSuiAddress(pubkey) -> Blake2b hash + bech32 encoding
normalizeSignature(sig) -> ensures s-value ≤ N/2 (required by SUI)

// In utils.mo
parseNat(text) -> safe text to number parsing
encodeBase64/decodeBase64 -> base64 encoding for RPC communication
hexEncode(bytes) -> hex string conversion
```

This modular structure makes it easy to:
- Add new tools (extend `wallet_tools.mo`)
- Support other blockchains (create new crypto modules)
- Reuse utilities across different features
- Test individual components independently

---

---

## 🛣️ Roadmap

- [x] Multi-tenant wallet architecture
- [x] Address derivation per principal
- [x] Balance queries via SUI RPC
- [ ] Complete transaction signing and broadcasting
- [ ] Support for SUI coin selection
- [ ] Gas estimation and optimization
- [ ] Support for SUI Move calls
- [ ] Transaction history tracking

---

## 📖 Resources

-   [SPEC.md](./SPEC.md) - Detailed technical specification
-   [Prometheus Protocol Docs](https://prometheusprotocol.org/docs)
-   [SUI Documentation](https://docs.sui.io/)
-   [IC Threshold ECDSA](https://internetcomputer.org/docs/current/developer-docs/integrations/t-ecdsa/)

---

## What's Next?

-   **Complete Transaction Implementation:** The `wallet_transfer` tool needs full transaction construction and signing
-   **Add More Features:** Consider adding support for SUI Move calls, NFTs, and other SUI features
-   **Learn More:** Check out the full [Service Developer Docs](https://prometheusprotocol.org/docs) for advanced topics# sui-wallet
