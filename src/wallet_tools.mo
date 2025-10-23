import Result "mo:base/Result";
import Nat64 "mo:base/Nat64";
import Json "mo:json";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import Types "./types";
import Utils "./utils";

module {
  public type WalletContext = {
    getSuiAddress : (caller : Principal) -> async Result.Result<Text, Text>;
    querySuiBalance : (address : Text) -> async Result.Result<Text, Text>;
    getSuiCoins : (address : Text) -> async Result.Result<[Types.SuiCoin], Text>;
    transferSuiSimple : (
      senderAddress : Text,
      coinObjectId : Text,
      recipientAddress : Text,
      amount : Nat64,
      gasBudget : Nat64,
      caller : Principal,
    ) -> async Result.Result<Text, Text>;
  };

  /// Tool: wallet_get_address
  public func walletGetAddressTool(
    ctx : WalletContext,
    _args : McpTypes.JsonValue,
    auth : ?AuthTypes.AuthInfo,
    cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> (),
  ) : async () {
    let caller = switch (auth) {
      case (?authInfo) { authInfo.principal };
      case (null) {
        return cb(#ok({ content = [#text({ text = "Authentication required" })]; isError = true; structuredContent = null }));
      };
    };

    switch (await ctx.getSuiAddress(caller)) {
      case (#ok(address)) {
        let structuredPayload = Json.obj([("address", Json.str(address))]);
        let stringified = Json.stringify(structuredPayload, null);
        cb(#ok({ content = [#text({ text = stringified })]; isError = false; structuredContent = ?structuredPayload }));
      };
      case (#err(msg)) {
        cb(#ok({ content = [#text({ text = "Error: " # msg })]; isError = true; structuredContent = null }));
      };
    };
  };

  /// Tool: wallet_get_balance
  public func walletGetBalanceTool(
    ctx : WalletContext,
    _args : McpTypes.JsonValue,
    auth : ?AuthTypes.AuthInfo,
    cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> (),
  ) : async () {
    let caller = switch (auth) {
      case (?authInfo) { authInfo.principal };
      case (null) {
        return cb(#ok({ content = [#text({ text = "Authentication required" })]; isError = true; structuredContent = null }));
      };
    };

    switch (await ctx.getSuiAddress(caller)) {
      case (#ok(address)) {
        switch (await ctx.querySuiBalance(address)) {
          case (#ok(balance)) {
            let structuredPayload = Json.obj([("balance", Json.str(balance))]);
            let stringified = Json.stringify(structuredPayload, null);
            cb(#ok({ content = [#text({ text = stringified })]; isError = false; structuredContent = ?structuredPayload }));
          };
          case (#err(msg)) {
            cb(#ok({ content = [#text({ text = "Error querying balance: " # msg })]; isError = true; structuredContent = null }));
          };
        };
      };
      case (#err(msg)) {
        cb(#ok({ content = [#text({ text = "Error getting address: " # msg })]; isError = true; structuredContent = null }));
      };
    };
  };

  /// Tool: wallet_transfer
  public func walletTransferTool(
    ctx : WalletContext,
    args : McpTypes.JsonValue,
    auth : ?AuthTypes.AuthInfo,
    cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> (),
  ) : async () {
    let caller = switch (auth) {
      case (?authInfo) { authInfo.principal };
      case (null) {
        return cb(#ok({ content = [#text({ text = "Authentication required" })]; isError = true; structuredContent = null }));
      };
    };

    let to_address = switch (Result.toOption(Json.getAsText(args, "to_address"))) {
      case (?addr) { addr };
      case (null) {
        return cb(#ok({ content = [#text({ text = "Missing 'to_address' parameter" })]; isError = true; structuredContent = null }));
      };
    };

    let amount_text = switch (Result.toOption(Json.getAsText(args, "amount"))) {
      case (?amt) { amt };
      case (null) {
        return cb(#ok({ content = [#text({ text = "Missing 'amount' parameter" })]; isError = true; structuredContent = null }));
      };
    };

    let amountNat = switch (Utils.parseNat(amount_text)) {
      case (?n) { n };
      case (null) {
        return cb(#ok({ content = [#text({ text = "Invalid amount format: must be a number" })]; isError = true; structuredContent = null }));
      };
    };
    let amount = Nat64.fromNat(amountNat);

    let senderAddress = switch (await ctx.getSuiAddress(caller)) {
      case (#ok(addr)) { addr };
      case (#err(msg)) {
        return cb(#ok({ content = [#text({ text = "Error getting sender address: " # msg })]; isError = true; structuredContent = null }));
      };
    };

    let coins = switch (await ctx.getSuiCoins(senderAddress)) {
      case (#ok(coinList)) { coinList };
      case (#err(msg)) {
        return cb(#ok({ content = [#text({ text = "Error getting coins: " # msg })]; isError = true; structuredContent = null }));
      };
    };

    if (coins.size() == 0) {
      let errorMsg = "Insufficient funds: No coins available in wallet.\n\n" #
      "Your SUI wallet address is: " # senderAddress # "\n\n" #
      "Please fund this EXACT address on SUI mainnet.\n" #
      "You can verify your balance at: https://suiscan.xyz/mainnet/account/" # senderAddress;
      return cb(#ok({ content = [#text({ text = errorMsg })]; isError = true; structuredContent = null }));
    };

    let coin = coins[0];

    let coinBalance = switch (Utils.parseNat(coin.balance)) {
      case (?b) { Nat64.fromNat(b) };
      case (null) {
        return cb(#ok({ content = [#text({ text = "Invalid coin balance" })]; isError = true; structuredContent = null }));
      };
    };

    let gasBudget : Nat64 = 10_000_000;
    if (coinBalance < amount + gasBudget) {
      return cb(#ok({ content = [#text({ text = "Insufficient funds: balance " # Nat64.toText(coinBalance) # " MIST, need " # Nat64.toText(amount + gasBudget) # " MIST" })]; isError = true; structuredContent = null }));
    };

    let txId = switch (await ctx.transferSuiSimple(senderAddress, coin.coinObjectId, to_address, amount, gasBudget, caller)) {
      case (#ok(digest)) { digest };
      case (#err(msg)) {
        return cb(#ok({ content = [#text({ text = "Error executing transfer: " # msg })]; isError = true; structuredContent = null }));
      };
    };

    let structuredPayload = Json.obj([
      ("status", Json.str("success")),
      ("transaction_id", Json.str(txId)),
    ]);
    let stringified = Json.stringify(structuredPayload, null);

    cb(#ok({ content = [#text({ text = stringified })]; isError = false; structuredContent = ?structuredPayload }));
  };
};
