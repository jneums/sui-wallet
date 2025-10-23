import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import IC "mo:ic";
import Json "mo:json";
import Crypto "./crypto";
import SuiRpc "./sui_rpc";
import Utils "./utils";

module {
  /// Transfer SUI using the unsafe_transferSui RPC method
  public func transferSuiSimple(
    rpcConfig : SuiRpc.RpcConfig,
    senderAddress : Text,
    coinObjectId : Text,
    recipientAddress : Text,
    amount : Nat64,
    gasBudget : Nat64,
    signFunc : (messageHash : Blob) -> async Result.Result<Blob, Text>,
    getPublicKeyFunc : () -> async Result.Result<Blob, Text>,
  ) : async Result.Result<Text, Text> {
    try {
      let request_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"unsafe_transferSui\"," #
      "\"params\":[\"" # senderAddress # "\",\"" # coinObjectId # "\",\"" #
      Nat64.toText(gasBudget) # "\",\"" # recipientAddress # "\",\"" # Nat64.toText(amount) # "\"]}";

      Debug.print("Transfer request: " # request_body);

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
        url = rpcConfig.rpcUrl;
        max_response_bytes = ?20000;
        headers = [{ name = "Content-Type"; value = "application/json" }];
        body = ?Text.encodeUtf8(request_body);
        method = #post;
        transform = ?{
          function = rpcConfig.transformFunc;
          context = Blob.fromArray([]);
        };
      });

      let body_text = switch (Text.decodeUtf8(response.body)) {
        case (?text) { text };
        case (null) { return #err("Failed to decode response") };
      };

      Debug.print("Transfer response: " # body_text);

      switch (Json.parse(body_text)) {
        case (#ok(json)) {
          switch (Json.get(json, "result")) {
            case (?result) {
              switch (Json.getAsText(result, "txBytes")) {
                case (#ok(txBytesBase64)) {
                  let txBytes = Utils.decodeBase64(txBytesBase64);

                  Debug.print("Transaction bytes size: " # Nat.toText(txBytes.size()));

                  // Create intent message for signing
                  let intent : [Nat8] = [0, 0, 0];
                  let messageToSign = Array.append(intent, txBytes);

                  // SUI requires Blake2b-256 hash of (intent + txBytes)
                  let messageHashBlob = Crypto.blake2bHash(messageToSign);
                  let messageHashBytes = Blob.toArray(messageHashBlob);
                  Debug.print("Blake2b hash size: " # Nat.toText(messageHashBytes.size()));
                  Debug.print("Message to sign (intent + txBytes): " # Nat.toText(messageToSign.size()) # " bytes");

                  if (messageHashBytes.size() != 32) {
                    return #err("Blake2b hash is not 32 bytes: " # Nat.toText(messageHashBytes.size()));
                  };

                  // Hash again with SHA256 before signing (per Rust example)
                  let finalHashBlob = Crypto.sha256Hash(messageHashBytes);
                  Debug.print("Final SHA256 hash size: " # Nat.toText(Blob.toArray(finalHashBlob).size()));

                  let signature = switch (await signFunc(finalHashBlob)) {
                    case (#ok(sig)) { Blob.toArray(sig) };
                    case (#err(msg)) { return #err("Failed to sign: " # msg) };
                  };

                  Debug.print("Signature size: " # Nat.toText(signature.size()));

                  let publicKey = switch (await getPublicKeyFunc()) {
                    case (#ok(pk)) { Blob.toArray(pk) };
                    case (#err(msg)) {
                      return #err("Failed to get public key: " # msg);
                    };
                  };

                  await SuiRpc.executeSuiTransaction(rpcConfig, txBytes, signature, publicKey);
                };
                case (#err(_)) { #err("No txBytes in response: " # body_text) };
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
      #err("Transfer failed: " # Error.message(e));
    };
  };
};
