import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Text "mo:base/Text";
import Base64 "mo:base64";

module {
  /// Helper to parse text to Nat
  public func parseNat(text : Text) : ?Nat {
    var n : Nat = 0;
    for (c in text.chars()) {
      let digit = switch (c) {
        case ('0') { 0 };
        case ('1') { 1 };
        case ('2') { 2 };
        case ('3') { 3 };
        case ('4') { 4 };
        case ('5') { 5 };
        case ('6') { 6 };
        case ('7') { 7 };
        case ('8') { 8 };
        case ('9') { 9 };
        case _ { return null };
      };
      n := n * 10 + digit;
    };
    ?n;
  };

  /// Helper to convert bytes to hex string
  public func hexEncode(bytes : [Nat8]) : Text {
    let hexChars = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"];
    var result = "";
    for (byte in bytes.vals()) {
      let high = Nat8.toNat(byte / 16);
      let low = Nat8.toNat(byte % 16);
      result #= hexChars[high] # hexChars[low];
    };
    result;
  };

  /// Helper to decode base64 string to bytes
  public func decodeBase64(base64Str : Text) : [Nat8] {
    let base64Decoder = Base64.Base64(#version(Base64.V2), ?false);
    base64Decoder.decode(base64Str);
  };

  /// Helper to encode bytes as base64
  public func encodeBase64(bytes : [Nat8]) : Text {
    let base64Chars = [
      'A',
      'B',
      'C',
      'D',
      'E',
      'F',
      'G',
      'H',
      'I',
      'J',
      'K',
      'L',
      'M',
      'N',
      'O',
      'P',
      'Q',
      'R',
      'S',
      'T',
      'U',
      'V',
      'W',
      'X',
      'Y',
      'Z',
      'a',
      'b',
      'c',
      'd',
      'e',
      'f',
      'g',
      'h',
      'i',
      'j',
      'k',
      'l',
      'm',
      'n',
      'o',
      'p',
      'q',
      'r',
      's',
      't',
      'u',
      'v',
      'w',
      'x',
      'y',
      'z',
      '0',
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '+',
      '/',
    ];
    var result = "";
    var i = 0;

    while (i < bytes.size()) {
      let b1 = bytes[i];
      let b2 = if (i + 1 < bytes.size()) { bytes[i + 1] } else { 0 : Nat8 };
      let b3 = if (i + 2 < bytes.size()) { bytes[i + 2] } else { 0 : Nat8 };

      let n = (Nat32.fromNat(Nat8.toNat(b1)) << 16) | (Nat32.fromNat(Nat8.toNat(b2)) << 8) | Nat32.fromNat(Nat8.toNat(b3));

      result #= Text.fromChar(base64Chars[Nat32.toNat((n >> 18) & 63)]);
      result #= Text.fromChar(base64Chars[Nat32.toNat((n >> 12) & 63)]);
      result #= if (i + 1 < bytes.size()) {
        Text.fromChar(base64Chars[Nat32.toNat((n >> 6) & 63)]);
      } else { "=" };
      result #= if (i + 2 < bytes.size()) {
        Text.fromChar(base64Chars[Nat32.toNat(n & 63)]);
      } else { "=" };

      i += 3;
    };

    result;
  };
};
