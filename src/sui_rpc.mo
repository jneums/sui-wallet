import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Result "mo:base/Result";
import Text "mo:base/Text";
import IC "mo:ic";
import Json "mo:json";
import Types "./types";
import Utils "./utils";

module {
  public type RpcConfig = {
    rpcUrl : Text;
    transformFunc : shared query ({
      response : IC.HttpRequestResult;
      context : Blob;
    }) -> async IC.HttpRequestResult;
  };

  /// Query SUI balance via RPC
  public func querySuiBalance(config : RpcConfig, address : Text) : async Result.Result<Text, Text> {
    try {
      let request_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"suix_getBalance\",\"params\":[\"" # address # "\"]}";

      let ic_management = actor ("aaaaa-aa") : actor {
        http_request : ({
          url : Text;
          max_response_bytes : ?Nat64;
          headers : [{ name : Text; value : Text }];
          body : ?Blob;
          method : { #get; #head; #post };
          transform : ?{
            function : shared query ({
              response : IC.HttpRequestResult;
              context : Blob;
            }) -> async IC.HttpRequestResult;
            context : Blob;
          };
        }) -> async IC.HttpRequestResult;
      };

      let response = await (with cycles = 300_000_000) ic_management.http_request({
        url = config.rpcUrl;
        max_response_bytes = ?10000;
        headers = [{ name = "Content-Type"; value = "application/json" }];
        body = ?Text.encodeUtf8(request_body);
        method = #post;
        transform = ?{
          function = config.transformFunc;
          context = Blob.fromArray([]);
        };
      });

      let body_text = switch (Text.decodeUtf8(response.body)) {
        case (?text) { text };
        case (null) { return #err("Failed to decode response") };
      };

      switch (Json.parse(body_text)) {
        case (#ok(json)) {
          switch (Json.get(json, "result")) {
            case (?result) {
              switch (Json.getAsText(result, "totalBalance")) {
                case (#ok(balance)) { #ok(balance) };
                case (#err(_)) { #err("Balance not found in response") };
              };
            };
            case (null) { #err("Result not found in response") };
          };
        };
        case (#err(_)) { #err("Failed to parse JSON response") };
      };
    } catch (e) {
      #err("HTTP request failed: " # Error.message(e));
    };
  };

  /// Get coins for a SUI address via RPC
  public func getSuiCoins(config : RpcConfig, address : Text) : async Result.Result<[Types.SuiCoin], Text> {
    try {
      Debug.print("Getting coins for address: " # address);
      let request_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"suix_getCoins\",\"params\":[\"" # address # "\",null,null,null]}";

      let ic_management = actor ("aaaaa-aa") : actor {
        http_request : ({
          url : Text;
          max_response_bytes : ?Nat64;
          headers : [{ name : Text; value : Text }];
          body : ?Blob;
          method : { #get; #head; #post };
          transform : ?{
            function : shared query ({
              response : IC.HttpRequestResult;
              context : Blob;
            }) -> async IC.HttpRequestResult;
            context : Blob;
          };
        }) -> async IC.HttpRequestResult;
      };

      let response = await (with cycles = 300_000_000) ic_management.http_request({
        url = config.rpcUrl;
        max_response_bytes = ?20000;
        headers = [{ name = "Content-Type"; value = "application/json" }];
        body = ?Text.encodeUtf8(request_body);
        method = #post;
        transform = ?{
          function = config.transformFunc;
          context = Blob.fromArray([]);
        };
      });

      let body_text = switch (Text.decodeUtf8(response.body)) {
        case (?text) { text };
        case (null) { return #err("Failed to decode response") };
      };

      Debug.print("SUI RPC Response: " # body_text);

      switch (Json.parse(body_text)) {
        case (#ok(json)) {
          switch (Json.get(json, "result")) {
            case (?result) {
              switch (Json.get(result, "data")) {
                case (?dataJson) {
                  var coins : [Types.SuiCoin] = [];

                  let dataArray = switch (dataJson) {
                    case (#array arr) { arr };
                    case _ { return #err("Data field is not an array") };
                  };

                  Debug.print("Parsing " # Nat.toText(dataArray.size()) # " coins from response");

                  for (coinJson in dataArray.vals()) {
                    let coinType = switch (Json.getAsText(coinJson, "coinType")) {
                      case (#ok(ct)) { ct };
                      case (#err(_)) { "" };
                    };
                    let coinObjectId = switch (Json.getAsText(coinJson, "coinObjectId")) {
                      case (#ok(id)) { id };
                      case (#err(_)) { "" };
                    };
                    let version = switch (Json.getAsText(coinJson, "version")) {
                      case (#ok(v)) { v };
                      case (#err(_)) { "0" };
                    };
                    let digest = switch (Json.getAsText(coinJson, "digest")) {
                      case (#ok(d)) { d };
                      case (#err(_)) { "" };
                    };
                    let balance = switch (Json.getAsText(coinJson, "balance")) {
                      case (#ok(b)) { b };
                      case (#err(_)) { "0" };
                    };

                    let coin : Types.SuiCoin = {
                      coinType = coinType;
                      coinObjectId = coinObjectId;
                      version = version;
                      digest = digest;
                      balance = balance;
                    };
                    coins := Array.append(coins, [coin]);
                    Debug.print("Parsed coin: " # coin.coinObjectId # " balance: " # coin.balance);
                  };

                  Debug.print("Total coins parsed: " # Nat.toText(coins.size()));
                  #ok(coins);
                };
                case (null) { #err("No data field in result") };
              };
            };
            case (null) { #err("No result in response") };
          };
        };
        case (#err(_)) { #err("Failed to parse JSON response") };
      };
    } catch (e) {
      #err("HTTP request failed: " # Error.message(e));
    };
  };

  /// Execute a signed SUI transaction
  public func executeSuiTransaction(
    config : RpcConfig,
    txBytes : [Nat8],
    signature : [Nat8],
    publicKey : [Nat8],
  ) : async Result.Result<Text, Text> {
    Debug.print("Executing transaction - signature size: " # Nat.toText(signature.size()) # ", pubkey size: " # Nat.toText(publicKey.size()));

    // SUI expects signatures in this format:
    // flag (1 byte) + signature (64 bytes) + public key (33 bytes)
    // The flag for ECDSA Secp256k1 is 0x01 per SUI documentation
    let flag : Nat8 = 0x01;
    let signatureWithScheme = Array.tabulate<Nat8>(
      1 + signature.size() + publicKey.size(),
      func(i : Nat) : Nat8 {
        if (i == 0) { flag } else if (i <= signature.size()) {
          signature[i - 1];
        } else { publicKey[i - signature.size() - 1] };
      },
    );

    Debug.print("Final signature blob size: " # Nat.toText(signatureWithScheme.size()));
    Debug.print("Signature flag: 0x" # Utils.hexEncode([signatureWithScheme[0]]));
    Debug.print("Signature r (first 8 bytes): 0x" # Utils.hexEncode(Array.tabulate<Nat8>(8, func(i) { signatureWithScheme[1 + i] })));
    Debug.print("Signature s (first 8 bytes): 0x" # Utils.hexEncode(Array.tabulate<Nat8>(8, func(i) { signatureWithScheme[33 + i] })));
    Debug.print("Public key (first 8 bytes): 0x" # Utils.hexEncode(Array.tabulate<Nat8>(8, func(i) { signatureWithScheme[65 + i] })));

    let txBytesBase64 = Utils.encodeBase64(txBytes);
    let signatureBase64 = Utils.encodeBase64(signatureWithScheme);

    Debug.print("Signature base64: " # signatureBase64);

    let request_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"sui_executeTransactionBlock\"," #
    "\"params\":[\"" # txBytesBase64 # "\",[\"" # signatureBase64 # "\"],null,null]}";

    try {
      let ic_management = actor ("aaaaa-aa") : actor {
        http_request : ({
          url : Text;
          max_response_bytes : ?Nat64;
          headers : [{ name : Text; value : Text }];
          body : ?Blob;
          method : { #get; #head; #post };
          transform : ?{
            function : shared query ({
              response : IC.HttpRequestResult;
              context : Blob;
            }) -> async IC.HttpRequestResult;
            context : Blob;
          };
        }) -> async IC.HttpRequestResult;
      };

      let response = await (with cycles = 500_000_000) ic_management.http_request({
        url = config.rpcUrl;
        max_response_bytes = ?30000;
        headers = [{ name = "Content-Type"; value = "application/json" }];
        body = ?Text.encodeUtf8(request_body);
        method = #post;
        transform = ?{
          function = config.transformFunc;
          context = Blob.fromArray([]);
        };
      });

      let body_text = switch (Text.decodeUtf8(response.body)) {
        case (?text) { text };
        case (null) { return #err("Failed to decode response") };
      };

      Debug.print("Execute response: " # body_text);

      switch (Json.parse(body_text)) {
        case (#ok(json)) {
          switch (Json.get(json, "result")) {
            case (?result) {
              switch (Json.getAsText(result, "digest")) {
                case (#ok(digest)) { #ok(digest) };
                case (#err(_)) { #err("No digest in response: " # body_text) };
              };
            };
            case (null) {
              switch (Json.get(json, "error")) {
                case (?error) {
                  let errorMsg = switch (Json.getAsText(error, "message")) {
                    case (#ok(msg)) { msg };
                    case (#err(_)) { body_text };
                  };
                  #err("SUI RPC error: " # errorMsg);
                };
                case (null) { #err("No result in response: " # body_text) };
              };
            };
          };
        };
        case (#err(_)) { #err("Failed to parse response: " # body_text) };
      };
    } catch (e) {
      #err("Execution failed: " # Error.message(e));
    };
  };
};
