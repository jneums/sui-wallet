module {
  // SUI RPC response types
  public type SuiCoin = {
    coinType : Text;
    coinObjectId : Text;
    version : Text;
    digest : Text;
    balance : Text;
  };

  public type SuiGasData = {
    payment : [{ objectId : Text; version : Nat; digest : Text }];
    owner : Text;
    price : Text;
    budget : Text;
  };
};
