# Omnibridge helpers contracts

## WETHOmnibridgeRouter

This contract allows reducing the number of actions required for native-to-erc20 bridging over Omnibridge.
An example of such bridging scenarios might be:
* Bridging ETH from Mainnet to the xDAI chain in a form of [WETH on xDAI](https://blockscout.com/poa/xdai/tokens/0x6A023CCd1ff6F2045C3309768eAd9E68F978f6e1/token-transfers)
* Bridging BNB from BSC to the xDAI chain in a form of [WBNB on xDAI](https://blockscout.com/poa/xdai/tokens/0xCa8d20f3e0144a72C6B5d576e9Bd3Fd8557E2B04/token-transfers)

Helper supports full-duplex bridging operations.
Thus, there are 2 main usage scenarios for the helper contract.

Even though the below examples are given for the BNB native coin from the BSC,
the mechanism works exactly the same for other native coins as well. 

### BNB => WBNB => WBNB on xDAI

In order to wrap native coins and bridge them through the Omnibridge to the other chain, make the following transaction:
* Call `Helper.wrapAndRelayTokens()`/`Helper.wrapAndRelayTokens(receiver)` in BSC
  
Desired bridged amount of BNB should be send as the transaction value argument.
If the given amount of BNB cannot be bridged immediately, the whole transaction will revert.

The upper call is identical to the following 3 sequential transactions:
* Call `WBNB.deposit()` in BSC
* Call `WBNB.approve(Omnibridge, value)` in BSC
* Call `Omnibridge.relayTokens(WBNB, value)` in BSC

### WBNB on xDAI => WBNB => BNB 

In order to bridged wrapped tokens back to the origin chain through the Omnibridge and automatically withdraw them, make the following transaction:
* Call `WBNB_on_xDAI.transferAndCall(Omnibridge, value, Helper ++ receiver)` in xDAI

Alternatively, make the following 2 transactions:
* Call `WBNB_on_xDAI.approve(Omnibridge, value)` in xDAI
* Call `Omnibridge.relayTokensAndCall(WBNB_on_xDAI, Helper, value, receiver)` in xDAI

It is crucially important to correctly specify the receiver in the upper approaches.
This should be an address of the final BNB receiver in BSC.
Always include it explicitly in the call, even if msg.sender is equal to the receiver.

The upper calls are identical to the following 3 sequential transactions:
* Call `WBNB_on_xDAI.approve(Omnibridge, value)` in xDAI
* Call `Omnibridge.relayTokens(WBNB_on_xDAI, value)` in xDAI
* Call `WBNB.withdraw(value - fee)` in BSC
