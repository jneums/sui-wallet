import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Int8 "mo:base/Int8";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import SuiAddress "mo:sui/address";
import Blake2b "mo:blake2b";
import Sha256 "mo:sha2/Sha256";
import Utils "./utils";

module {
  public type PublicKey = Blob;
  public type Signature = [Nat8];

  /// Hash message with Blake2b-256 (required by SUI for transaction signing)
  public func blake2bHash(message : [Nat8]) : Blob {
    // SUI requires Blake2b with 32-byte output (Blake2b-256)
    let config = {
      digest_length = 32; // 32 bytes = 256 bits
      key = null;
      salt = null;
      personal = null;
    };
    Blake2b.hash(Blob.fromArray(message), ?config);
  };

  /// Hash message with SHA256 (used for double-hashing before IC ECDSA)
  public func sha256Hash(message : [Nat8]) : Blob {
    Sha256.fromArray(#sha256, message);
  };

  /// Convert ECDSA public key to SUI address using proper Blake2b hashing
  public func publicKeyToSuiAddress(publicKey : PublicKey) : Result.Result<Text, Text> {
    let pkBytes = Blob.toArray(publicKey);

    Debug.print("Public key size: " # Nat.toText(pkBytes.size()) # " bytes, first byte: 0x" # Nat8.toText(pkBytes[0]));

    // Compress public key if needed
    let compressedKey = if (pkBytes.size() == 65) {
      // Uncompressed key format: 0x04 || x (32 bytes) || y (32 bytes)
      // Compressed format: (0x02 or 0x03) || x (32 bytes)
      let yLast = pkBytes[64];
      let prefix : Nat8 = if (yLast % 2 == 0) { 0x02 } else { 0x03 };

      let compressed = Array.tabulate<Nat8>(
        33,
        func(i) {
          if (i == 0) { prefix } else { pkBytes[i] };
        },
      );
      Debug.print("Compressed key prefix: " # Nat8.toText(prefix));
      compressed;
    } else if (pkBytes.size() == 33) {
      Debug.print("Public key already compressed, using as-is");
      pkBytes;
    } else {
      return #err("Invalid public key size: " # Nat.toText(pkBytes.size()));
    };

    // Use mo:sui's proper Blake2b-based address derivation
    switch (SuiAddress.publicKeyToAddress(compressedKey, #Secp256k1)) {
      case (#ok(address)) {
        Debug.print("Derived SUI address: " # address);
        #ok(address);
      };
      case (#err(msg)) { #err(msg) };
    };
  };

  /// Normalize ECDSA signature to ensure s-value is low (required by SUI)
  public func normalizeSignature(sig : Signature) : Signature {
    if (sig.size() != 64) {
      return sig;
    };

    let curveOrder : [Nat8] = [
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFE,
      0xBA,
      0xAE,
      0xDC,
      0xE6,
      0xAF,
      0x48,
      0xA0,
      0x3B,
      0xBF,
      0xD2,
      0x5E,
      0x8C,
      0xD0,
      0x36,
      0x41,
      0x41,
    ];

    let halfOrder : [Nat8] = [
      0x7F,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0x5D,
      0x57,
      0x6E,
      0x73,
      0x57,
      0xA4,
      0x50,
      0x1D,
      0xDF,
      0xE9,
      0x2F,
      0x46,
      0x68,
      0x1B,
      0x20,
      0xA0,
    ];

    let sOriginal = Array.tabulate<Nat8>(32, func(i) { sig[32 + i] });

    Debug.print("s value (first 8 bytes): " # Utils.hexEncode(Array.tabulate<Nat8>(8, func(i) { sOriginal[i] })));
    Debug.print("N/2 (first 8 bytes): " # Utils.hexEncode(Array.tabulate<Nat8>(8, func(i) { halfOrder[i] })));

    var cmp : Int8 = 0;
    label compareLoop for (i in Array.keys(sOriginal)) {
      if (sOriginal[i] > halfOrder[i]) {
        cmp := 1;
        Debug.print("s > N/2 at byte " # Nat.toText(i));
        break compareLoop;
      } else if (sOriginal[i] < halfOrder[i]) {
        cmp := -1;
        Debug.print("s < N/2 at byte " # Nat.toText(i));
        break compareLoop;
      };
    };

    if (cmp != 1) {
      Debug.print("Signature already has low s-value, no normalization needed");
      return sig;
    };

    Debug.print("Normalizing high s-value: computing s' = N - s");

    var borrow : Nat = 0;
    let s = Array.init<Nat8>(32, 0);
    for (i in Array.keys(sOriginal)) {
      let idx = 31 - i;
      let sVal = Nat8.toNat(sOriginal[idx]);
      let nVal = Nat8.toNat(curveOrder[idx]);

      let temp = if (nVal >= sVal + borrow) {
        nVal - sVal - borrow;
      } else {
        nVal + 256 - sVal - borrow;
      };
      s[idx] := Nat8.fromNat(temp % 256);
      borrow := if (nVal < sVal + borrow) { 1 } else { 0 };
    };

    let normalizedSig = Array.tabulate<Nat8>(
      64,
      func(i : Nat) : Nat8 {
        if (i < 32) {
          sig[i];
        } else {
          s[i - 32];
        };
      },
    );

    Debug.print("Signature normalized successfully");
    normalizedSig;
  };
};
