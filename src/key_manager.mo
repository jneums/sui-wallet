import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Map "mo:map/Map";
import Crypto "./crypto";

import { ic } "mo:ic";

module {
  public type KeyCache = Map.Map<Principal, Blob>;

  public type KeyConfig = {
    keyName : Text;
    canisterSalt : Blob;
  };

  /// Get the unique derivation path for a given principal
  public func getDerivationPath(config : KeyConfig, caller : Principal) : [Blob] {
    [config.canisterSalt, Principal.toBlob(caller)];
  };

  /// Derive the ECDSA public key for a given principal
  public func getPublicKey(
    config : KeyConfig,
    cache : KeyCache,
    caller : Principal,
  ) : async Result.Result<Blob, Text> {
    // Check cache first
    switch (Map.get(cache, Map.phash, caller)) {
      case (?cachedKey) {
        Debug.print("Using cached public key for principal: " # Principal.toText(caller));
        return #ok(cachedKey);
      };
      case (null) {
        Debug.print("Deriving new public key for principal: " # Principal.toText(caller));
      };
    };

    let derivation_path = getDerivationPath(config, caller);
    Debug.print("Derivation path length: " # Nat.toText(derivation_path.size()));

    try {
      let response = await (with cycles = 10_000_000_000) ic.ecdsa_public_key({
        canister_id = null;
        derivation_path = derivation_path;
        key_id = { curve = #secp256k1; name = config.keyName };
      });

      let pkBytes = Blob.toArray(response.public_key);
      Debug.print("Raw public key from IC: size=" # Nat.toText(pkBytes.size()) # ", first byte=" # Nat8.toText(pkBytes[0]));

      // Cache the result
      Map.set(cache, Map.phash, caller, response.public_key);

      #ok(response.public_key);
    } catch (e) {
      #err("Failed to get public key: " # Error.message(e));
    };
  };

  /// Sign a message with the caller's derived key
  public func signWithCallerKey(
    config : KeyConfig,
    caller : Principal,
    messageHash : Blob,
  ) : async Result.Result<Blob, Text> {
    let derivation_path = getDerivationPath(config, caller);

    try {
      let response = await (with cycles = 10_000_000_000) ic.sign_with_ecdsa({
        message_hash = messageHash;
        derivation_path = derivation_path;
        key_id = { curve = #secp256k1; name = config.keyName };
      });

      let sigBytes = Blob.toArray(response.signature);
      Debug.print("Raw signature from IC: size=" # Nat.toText(sigBytes.size()));

      let normalizedSig = Crypto.normalizeSignature(sigBytes);
      Debug.print("Normalized signature size: " # Nat.toText(normalizedSig.size()));

      #ok(Blob.fromArray(normalizedSig));
    } catch (e) {
      #err("Failed to sign: " # Error.message(e));
    };
  };
};
