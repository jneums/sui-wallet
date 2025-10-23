### **Project Specification: Multi-Tenant SUI Wallet MCP Server**

**Version:** 3.0
**Date:** October 23, 2025

#### **1. Project Goal & Overview**

The objective is to create a **multi-tenant, non-custodial SUI wallet canister** that functions as an MCP server. This canister will provide any principal on the Internet Computer (user or canister) with its own unique, secure SUI wallet, derived from its Principal ID.

The service will expose a set of simple "tools" that abstract away all complexities of SUI blockchain interaction. It will leverage the IC's native **threshold ECDSA** for decentralized, high-security key management, ensuring that each user's signing capability is tied directly to their IC identity.

#### **2. Core Architecture**

The architecture is fully on-chain and designed for multi-tenancy.

1.  **Calling Principal (User/Agent):** The end-user of the service. Each unique principal is a distinct "tenant."
2.  **Wallet MCP Canister (This Project):** The "brain" of the operation. It exposes the public toolset and orchestrates all logic. It is stateless regarding user keys but manages the logic for deriving them on-the-fly.
3.  **IC Management Canister (System):** The secure "hand." Provides `ecdsa_public_key` and `sign_with_ecdsa` functions, which are used to generate keys and signatures based on a derivation path unique to each calling principal.
4.  **SUI RPC Node (External):** Communicated with via HTTP outcalls.

**Key Architectural Shift:** The Wallet Canister no longer has a single identity. Instead, it acts as a secure proxy, deriving a unique SUI wallet for **each calling principal** that interacts with it.

#### **3. MCP Tool Definitions**

The canister MUST expose the following tools. The `caller` of the tool is implicitly the owner of the wallet being operated on.

##### **Tool 1: `wallet_get_address`**
*   **`name`**: `wallet_get_address`
*   **`description`**: "Retrieves the unique SUI address associated with your Principal ID. This address is deterministically derived from your IC identity."
*   **`inputSchema`**: `{ "type": "object", "properties": {} }` (No inputs required)
*   **`outputSchema`**:
    ```json
    {
      "type": "object",
      "properties": {
        "address": {
          "type": "string",
          "description": "The public SUI address for your principal."
        }
      },
      "required": ["address"]
    }
    ```

##### **Tool 2: `wallet_get_balance`**
*   **`name`**: `wallet_get_balance`
*   **`description`**: "Retrieves the current SUI balance for the wallet associated with your Principal ID."
*   **`inputSchema`**: `{ "type": "object", "properties": {} }`
*   **`outputSchema`**:
    ```json
    {
      "type": "object",
      "properties": {
        "balance": {
          "type": "string",
          "description": "The total SUI balance in MIST (1 SUI = 1,000,000,000 MIST)."
        }
      },
      "required": ["balance"]
    }
    ```

##### **Tool 3: `wallet_transfer`**
*   **`name`**: `wallet_transfer`
*   **`description`**: "Transfers SUI from your managed wallet to a destination address. The canister handles all transaction creation, signing on your behalf, and broadcasting."
*   **`inputSchema`**:
    ```json
    {
      "type": "object",
      "properties": {
        "to_address": {
          "type": "string",
          "description": "The destination SUI address."
        },
        "amount": {
          "type": "string",
          "description": "The amount of SUI to transfer, in MIST."
        }
      },
      "required": ["to_address", "amount"]
    }
    ```
*   **`outputSchema`**:
    ```json
    {
      "type": "object",
      "properties": {
        "status": {
          "type": "string",
          "description": "Confirmation that the transfer was successful."
        },
        "transaction_id": {
          "type": "string",
          "description": "The transaction digest/ID on the SUI network."
        }
      },
      "required": ["status", "transaction_id"]
    }
    ```

#### **4. Core Logic & Implementation Details**

##### **4.1. Multi-Tenant Identity and Key Management**

This is the most critical component. The canister MUST derive a unique, deterministic key for each calling principal.

1.  **Derivation Path Scheme:** The derivation path for the threshold ECDSA calls MUST be a combination of a canister-specific salt and the caller's principal.
    *   **Example:** `derivation_path = [canister_salt_blob, caller.to_blob()]`.
    *   The `canister_salt_blob` MUST be a stable, private variable within the canister to ensure all derived keys are unique to this service.
2.  **On-the-Fly Derivation:** For every incoming tool call, the canister MUST perform the following steps:
    a. Get the `caller`'s `Principal`.
    b. Construct the unique `derivation_path` for that principal.
    c. Use this path to call `ecdsa_public_key` and derive the caller's SUI address.

##### **4.2. `wallet_transfer` Tool Logic**

The workflow is now contextual to the caller:

1.  **Get Caller Identity:** Get the `caller`'s `Principal` from the message.
2.  **Derive Caller's Address:** Construct the caller-specific derivation path and derive their SUI address.
3.  **Get Caller's Gas Coins:** Perform an HTTP outcall to `sui_getCoins`, querying for coins owned by the **caller's derived SUI address**.
4.  **Construct Transaction Intent:** Use `mo:sui` to create the `TransactionData` record. The `sender` field MUST be the caller's derived address.
5.  **Serialize & Hash:** Use `mo:bcs` to serialize the `TransactionData` and hash it.
6.  **Sign on Behalf of Caller:** Call `sign_with_ecdsa` using the **caller's unique derivation path** and the message hash.
7.  **Broadcast & Finalize:** Broadcast the transaction via HTTP outcall using `sui_executeTransactionBlock` with the `WaitForEffectsCert` option.
8.  **Return Result:** Return the transaction digest or an error to the caller.

#### **5. Dependencies**

*   **Motoko SUI Library (`mo:sui`)**
*   **Motoko BCS Library (`mo:bcs`)**
*   **IC Management Canister**
*   **SUI RPC Node URL**

#### **6. Testing & Acceptance Criteria**

Testing must rigorously validate the multi-tenant security and isolation model.

1.  **Multi-Principal Tests:** All tests must be conducted using at least two distinct test principals (`Principal_A`, `Principal_B`).
2.  **Address Uniqueness:**
    *   `Principal_A` calls `wallet_get_address` and receives `Address_A`.
    *   `Principal_B` calls `wallet_get_address` and receives `Address_B`.
    *   The test MUST assert that `Address_A != Address_B`.
3.  **State Isolation E2E Test (SUI Testnet):**
    *   Fund `Address_A` with testnet SUI. `Address_B` remains unfunded.
    *   `Principal_B` calls `wallet_transfer`. The call MUST fail with an "Insufficient Funds" error.
    *   `Principal_A` calls `wallet_transfer`. The call MUST succeed.
    *   The test must verify that `Principal_A`'s balance has decreased, and `Principal_B`'s balance remains zero.

#### **7. Deliverables**

1.  The complete, well-documented Motoko source code for the **Multi-Tenant Wallet MCP Canister**.
2.  A comprehensive test suite (`mops test`) covering all acceptance criteria, with a focus on multi-tenant scenarios.
3.  A `README.md` file with clear instructions on deployment, configuration, and tool usage, explaining how each principal gets its own unique wallet.