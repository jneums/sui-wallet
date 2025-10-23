import Result "mo:base/Result";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Option "mo:base/Option";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Time "mo:base/Time";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";

import HttpTypes "mo:http-types";
import Map "mo:map/Map";
import Json "mo:json";

import AuthCleanup "mo:mcp-motoko-sdk/auth/Cleanup";
import AuthState "mo:mcp-motoko-sdk/auth/State";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";

import Mcp "mo:mcp-motoko-sdk/mcp/Mcp";
import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import HttpHandler "mo:mcp-motoko-sdk/mcp/HttpHandler";
import Cleanup "mo:mcp-motoko-sdk/mcp/Cleanup";
import State "mo:mcp-motoko-sdk/mcp/State";
import Payments "mo:mcp-motoko-sdk/mcp/Payments";
import HttpAssets "mo:mcp-motoko-sdk/mcp/HttpAssets";
import Beacon "mo:mcp-motoko-sdk/mcp/Beacon";
import ApiKey "mo:mcp-motoko-sdk/auth/ApiKey";

import SrvTypes "mo:mcp-motoko-sdk/server/Types";

import IC "mo:ic";

// Local modules
import Types "./types";
import Crypto "./crypto";
import WalletTools "./wallet_tools";
import KeyManager "./key_manager";
import SuiRpc "./sui_rpc";
import SuiTx "./sui_tx";

shared ({ caller = deployer }) persistent actor class McpServer(
  args : ?{
    owner : ?Principal;
  }
) = self {

  // The canister owner, who can manage treasury funds.
  // Defaults to the deployer if not specified.
  var owner : Principal = Option.get(do ? { args!.owner! }, deployer);

  // =================================================================================
  // --- SUI WALLET CONFIGURATION ---
  // =================================================================================

  // Canister-specific salt for deriving unique keys per principal
  // Using a simple version byte like the Rust example for compatibility
  let CANISTER_SALT : Blob = Blob.fromArray([1 : Nat8]); // Schema V1

  // SUI RPC endpoint (testnet)
  let SUI_RPC_URL : Text = "https://fullnode.testnet.sui.io:443";

  // ECDSA key name for IC threshold signatures
  let KEY_NAME : Text = "test_key_1"; // Use "key_1" for mainnet

  // State for certified HTTP assets (like /.well-known/...)
  var stable_http_assets : HttpAssets.StableEntries = [];
  transient let http_assets = HttpAssets.init(stable_http_assets);

  // Cache for derived public keys (principal -> public key)
  // Keys are deterministic, so we can cache them to avoid repeated ECDSA calls
  let publicKeyCache = Map.new<Principal, Blob>();

  // The application context that holds our state.
  var appContext : McpTypes.AppContext = State.init([]);

  // =================================================================================
  // --- OPT-IN: MONETIZATION & AUTHENTICATION ---
  // Authentication is ENABLED for the SUI wallet to identify each principal
  // =================================================================================

  let issuerUrl = "https://bfggx-7yaaa-aaaai-q32gq-cai.icp0.io";
  let allowanceUrl = "https://prometheusprotocol.org/app/io.github.jneums.sui-wallet";
  let requiredScopes = ["openid"];

  //function to transform the response for jwks client
  public query func transformJwksResponse({
    context : Blob;
    response : IC.HttpRequestResult;
  }) : async IC.HttpRequestResult {
    ignore context; // Required by signature
    {
      response with headers = []; // not intersted in the headers
    };
  };

  // Transform function for SUI RPC HTTP outcalls
  public query func transformSuiResponse({
    context : Blob;
    response : IC.HttpRequestResult;
  }) : async IC.HttpRequestResult {
    ignore context; // Required by signature
    {
      status = response.status;
      headers = []; // Remove headers to ensure consensus
      body = response.body;
    };
  };

  // Initialize the auth context with the issuer URL and required scopes.
  let authContext : ?AuthTypes.AuthContext = ?AuthState.init(
    Principal.fromActor(self),
    owner,
    issuerUrl,
    requiredScopes,
    transformJwksResponse,
  );

  // =================================================================================
  // --- OPT-IN: USAGE ANALYTICS (BEACON) ---
  // To enable anonymous usage analytics, uncomment the `beaconContext` initialization.
  // This helps the Prometheus Protocol DAO understand ecosystem growth.
  // =================================================================================

  transient let beaconContext : ?Beacon.BeaconContext = null;

  // --- UNCOMMENT THIS BLOCK TO ENABLE THE BEACON ---
  /*
  let beaconCanisterId = Principal.fromText("m63pw-fqaaa-aaaai-q33pa-cai");
  transient let beaconContext : ?Beacon.BeaconContext = ?Beacon.init(
      beaconCanisterId, // Public beacon canister ID
      ?(15 * 60), // Send a beacon every 15 minutes
  );
  */
  // --- END OF BEACON BLOCK ---

  // --- Timers ---
  Cleanup.startCleanupTimer<system>(appContext);

  // The AuthCleanup timer only needs to run if authentication is enabled.
  switch (authContext) {
    case (?ctx) { AuthCleanup.startCleanupTimer<system>(ctx) };
    case (null) { Debug.print("Authentication is disabled.") };
  };

  // The Beacon timer only needs to run if the beacon is enabled.
  switch (beaconContext) {
    case (?ctx) { Beacon.startTimer<system>(ctx) };
    case (null) { Debug.print("Beacon is disabled.") };
  };

  // =================================================================================
  // --- SUI WALLET HELPER FUNCTIONS ---
  // =================================================================================

  /// Key configuration for ECDSA operations
  let keyConfig : KeyManager.KeyConfig = {
    keyName = KEY_NAME;
    canisterSalt = CANISTER_SALT;
  };

  /// RPC configuration for SUI operations
  let rpcConfig : SuiRpc.RpcConfig = {
    rpcUrl = SUI_RPC_URL;
    transformFunc = transformSuiResponse;
  };

  /// Derive the ECDSA public key for a given principal
  func getPublicKey(caller : Principal) : async Result.Result<Blob, Text> {
    await KeyManager.getPublicKey(keyConfig, publicKeyCache, caller);
  };

  /// Convert ECDSA public key to SUI address using proper Blake2b hashing
  func publicKeyToSuiAddress(publicKey : Blob) : Result.Result<Text, Text> {
    Crypto.publicKeyToSuiAddress(publicKey);
  };

  /// Get SUI address for a given principal
  func getSuiAddress(caller : Principal) : async Result.Result<Text, Text> {
    switch (await getPublicKey(caller)) {
      case (#ok(pubKey)) {
        publicKeyToSuiAddress(pubKey);
      };
      case (#err(msg)) { #err(msg) };
    };
  };

  /// Query SUI balance via RPC
  func querySuiBalance(address : Text) : async Result.Result<Text, Text> {
    await SuiRpc.querySuiBalance(rpcConfig, address);
  };

  /// Get coins for a SUI address via RPC
  func getSuiCoins(address : Text) : async Result.Result<[Types.SuiCoin], Text> {
    await SuiRpc.getSuiCoins(rpcConfig, address);
  };

  /// Transfer SUI using the simpler sui_transferSui RPC method
  func transferSuiSimple(
    senderAddress : Text,
    coinObjectId : Text,
    recipientAddress : Text,
    amount : Nat64,
    gasBudget : Nat64,
    caller : Principal,
  ) : async Result.Result<Text, Text> {
    let signFunc = func(messageHash : Blob) : async Result.Result<Blob, Text> {
      await KeyManager.signWithCallerKey(keyConfig, caller, messageHash);
    };
    let getKeyFunc = func() : async Result.Result<Blob, Text> {
      await getPublicKey(caller);
    };
    await SuiTx.transferSuiSimple(
      rpcConfig,
      senderAddress,
      coinObjectId,
      recipientAddress,
      amount,
      gasBudget,
      signFunc,
      getKeyFunc,
    );
  };

  // --- 1. DEFINE YOUR RESOURCES & TOOLS ---
  transient let resources : [McpTypes.Resource] = [
    {
      uri = "file:///SPEC.md";
      name = "SPEC.md";
      title = ?"SUI Wallet Specification";
      description = ?"Technical specification for the multi-tenant SUI wallet";
      mimeType = ?"text/markdown";
    },
  ];

  transient let tools : [McpTypes.Tool] = [
    {
      name = "wallet_get_address";
      title = ?"Get SUI Address";
      description = ?"Retrieves the unique SUI address associated with your Principal ID. This address is deterministically derived from your IC identity.";
      inputSchema = Json.obj([
        ("type", Json.str("object")),
        ("properties", Json.obj([])),
      ]);
      outputSchema = ?Json.obj([
        ("type", Json.str("object")),
        ("properties", Json.obj([("address", Json.obj([("type", Json.str("string")), ("description", Json.str("The public SUI address for your principal."))]))])),
        ("required", Json.arr([Json.str("address")])),
      ]);
      payment = null;
    },
    {
      name = "wallet_get_balance";
      title = ?"Get SUI Balance";
      description = ?"Retrieves the current SUI balance for the wallet associated with your Principal ID.";
      inputSchema = Json.obj([
        ("type", Json.str("object")),
        ("properties", Json.obj([])),
      ]);
      outputSchema = ?Json.obj([
        ("type", Json.str("object")),
        ("properties", Json.obj([("balance", Json.obj([("type", Json.str("string")), ("description", Json.str("The total SUI balance in MIST (1 SUI = 1,000,000,000 MIST)."))]))])),
        ("required", Json.arr([Json.str("balance")])),
      ]);
      payment = null;
    },
    {
      name = "wallet_transfer";
      title = ?"Transfer SUI";
      description = ?"Transfers SUI from your managed wallet to a destination address. The canister handles all transaction creation, signing on your behalf, and broadcasting.";
      inputSchema = Json.obj([
        ("type", Json.str("object")),
        ("properties", Json.obj([("to_address", Json.obj([("type", Json.str("string")), ("description", Json.str("The destination SUI address."))])), ("amount", Json.obj([("type", Json.str("string")), ("description", Json.str("The amount of SUI to transfer, in MIST."))]))])),
        ("required", Json.arr([Json.str("to_address"), Json.str("amount")])),
      ]);
      outputSchema = ?Json.obj([
        ("type", Json.str("object")),
        ("properties", Json.obj([("status", Json.obj([("type", Json.str("string")), ("description", Json.str("Confirmation that the transfer was successful."))])), ("transaction_id", Json.obj([("type", Json.str("string")), ("description", Json.str("The transaction digest/ID on the SUI network."))]))])),
        ("required", Json.arr([Json.str("status"), Json.str("transaction_id")])),
      ]);
      payment = null;
    },
  ];

  // --- 2. DEFINE YOUR TOOL LOGIC ---

  // Create wallet context for tool implementations
  transient let walletContext : WalletTools.WalletContext = {
    getSuiAddress = getSuiAddress;
    querySuiBalance = querySuiBalance;
    getSuiCoins = getSuiCoins;
    transferSuiSimple = transferSuiSimple;
  };

  func walletGetAddressTool(args : McpTypes.JsonValue, auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {
    await WalletTools.walletGetAddressTool(walletContext, args, auth, cb);
  };

  func walletGetBalanceTool(args : McpTypes.JsonValue, auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {
    await WalletTools.walletGetBalanceTool(walletContext, args, auth, cb);
  };

  func walletTransferTool(args : McpTypes.JsonValue, auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {
    await WalletTools.walletTransferTool(walletContext, args, auth, cb);
  };

  // --- 3. CONFIGURE THE SDK ---
  transient let mcpConfig : McpTypes.McpConfig = {
    self = Principal.fromActor(self);
    allowanceUrl = ?allowanceUrl;
    serverInfo = {
      name = "io.github.jneums.sui-wallet";
      title = "SUI Wallet";
      version = "0.1.0";
    };
    resources = resources;
    resourceReader = func(uri) {
      Map.get(appContext.resourceContents, Map.thash, uri);
    };
    tools = tools;
    toolImplementations = [
      ("wallet_get_address", walletGetAddressTool),
      ("wallet_get_balance", walletGetBalanceTool),
      ("wallet_transfer", walletTransferTool),
    ];
    beacon = beaconContext;
  };

  // --- 4. CREATE THE SERVER LOGIC ---
  transient let mcpServer = Mcp.createServer(mcpConfig);

  // --- PUBLIC ENTRY POINTS ---

  // Do not remove these public methods below. They are required for the MCP Registry and MCP Orchestrator
  // to manage the canister upgrades and installs, handle payments, and allow owner only methods.

  /// Get the current owner of the canister.
  public query func get_owner() : async Principal { return owner };

  /// Set a new owner for the canister. Only the current owner can call this.
  public shared ({ caller }) func set_owner(new_owner : Principal) : async Result.Result<(), Payments.TreasuryError> {
    if (caller != owner) { return #err(#NotOwner) };
    owner := new_owner;
    return #ok(());
  };

  /// Get the canister's balance of a specific ICRC-1 token.
  public shared func get_treasury_balance(ledger_id : Principal) : async Nat {
    return await Payments.get_treasury_balance(Principal.fromActor(self), ledger_id);
  };

  /// Withdraw tokens from the canister's treasury to a specified destination.
  public shared ({ caller }) func withdraw(
    ledger_id : Principal,
    amount : Nat,
    destination : Payments.Destination,
  ) : async Result.Result<Nat, Payments.TreasuryError> {
    return await Payments.withdraw(
      caller,
      owner,
      ledger_id,
      amount,
      destination,
    );
  };

  // Helper to create the HTTP context for each request.
  private func _create_http_context() : HttpHandler.Context {
    return {
      self = Principal.fromActor(self);
      active_streams = appContext.activeStreams;
      mcp_server = mcpServer;
      streaming_callback = http_request_streaming_callback;
      // This passes the optional auth context to the handler.
      // If it's `null`, the handler will skip all auth checks.
      auth = authContext;
      http_asset_cache = ?http_assets.cache;
      mcp_path = ?"/mcp";
    };
  };

  /// Handle incoming HTTP requests.
  public query func http_request(req : SrvTypes.HttpRequest) : async SrvTypes.HttpResponse {
    let ctx : HttpHandler.Context = _create_http_context();
    // Ask the SDK to handle the request
    switch (HttpHandler.http_request(ctx, req)) {
      case (?mcpResponse) {
        // The SDK handled it, so we return its response.
        return mcpResponse;
      };
      case (null) {
        // The SDK ignored it. Now we can handle our own custom routes.
        if (req.url == "/") {
          // e.g., Serve a frontend asset
          return {
            status_code = 200;
            headers = [("Content-Type", "text/html")];
            body = Text.encodeUtf8("<h1>My Canister Frontend</h1>");
            upgrade = null;
            streaming_strategy = null;
          };
        } else {
          // Return a 404 for any other unhandled routes.
          return {
            status_code = 404;
            headers = [];
            body = Blob.fromArray([]);
            upgrade = null;
            streaming_strategy = null;
          };
        };
      };
    };
  };

  /// Handle incoming HTTP requests that modify state (e.g., POST).
  public shared func http_request_update(req : SrvTypes.HttpRequest) : async SrvTypes.HttpResponse {
    let ctx : HttpHandler.Context = _create_http_context();

    // Ask the SDK to handle the request
    let mcpResponse = await HttpHandler.http_request_update(ctx, req);

    switch (mcpResponse) {
      case (?res) {
        // The SDK handled it.
        return res;
      };
      case (null) {
        // The SDK ignored it. Handle custom update calls here.
        return {
          status_code = 404;
          headers = [];
          body = Blob.fromArray([]);
          upgrade = null;
          streaming_strategy = null;
        };
      };
    };
  };

  /// Handle streaming callbacks for large HTTP responses.
  public query func http_request_streaming_callback(token : HttpTypes.StreamingToken) : async ?HttpTypes.StreamingCallbackResponse {
    let ctx : HttpHandler.Context = _create_http_context();
    return HttpHandler.http_request_streaming_callback(ctx, token);
  };

  // --- CANISTER LIFECYCLE MANAGEMENT ---

  system func preupgrade() {
    stable_http_assets := HttpAssets.preupgrade(http_assets);
  };

  system func postupgrade() {
    HttpAssets.postupgrade(http_assets);
  };

  /**
   * Creates a new API key. This API key is linked to the caller's principal.
   * @param name A human-readable name for the key.
   * @returns The raw, unhashed API key. THIS IS THE ONLY TIME IT WILL BE VISIBLE.
   */
  public shared (msg) func create_my_api_key(name : Text, scopes : [Text]) : async Text {
    switch (authContext) {
      case (null) {
        Debug.trap("Authentication is not enabled on this canister.");
      };
      case (?ctx) {
        return await ApiKey.create_my_api_key(
          ctx,
          msg.caller,
          name,
          scopes,
        );
      };
    };
  };

  /** Revoke (delete) an API key owned by the caller.
   * @param key_id The ID of the key to revoke.
   * @returns True if the key was found and revoked, false otherwise.
   */
  public shared (msg) func revoke_my_api_key(key_id : Text) : async () {
    switch (authContext) {
      case (null) {
        Debug.trap("Authentication is not enabled on this canister.");
      };
      case (?ctx) {
        return ApiKey.revoke_my_api_key(ctx, msg.caller, key_id);
      };
    };
  };

  /** List all API keys owned by the caller.
   * @returns A list of API key metadata (but not the raw keys).
   */
  public query (msg) func list_my_api_keys() : async [AuthTypes.ApiKeyMetadata] {
    switch (authContext) {
      case (null) {
        Debug.trap("Authentication is not enabled on this canister.");
      };
      case (?ctx) {
        return ApiKey.list_my_api_keys(ctx, msg.caller);
      };
    };
  };

  public type UpgradeFinishedResult = {
    #InProgress : Nat;
    #Failed : (Nat, Text);
    #Success : Nat;
  };
  private func natNow() : Nat {
    return Int.abs(Time.now());
  };
  /* Return success after post-install/upgrade operations complete.
   * The Nat value is a timestamp (in nanoseconds) of when the upgrade finished.
   * If the upgrade is still in progress, return #InProgress with a timestamp of when it started.
   * If the upgrade failed, return #Failed with a timestamp and an error message.
   */
  public func icrc120_upgrade_finished() : async UpgradeFinishedResult {
    #Success(natNow());
  };
};
