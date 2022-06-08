# MULTI-AMB-ERC20-TO-ERC677 extension call flows

The call flows below document sequences of contracts methods invocations to cover the main MULTI-AMB-ERC20-TO-ERC677 extension operations.

## Tokens relay scenarios

* Foreign Native ERC20 token -> Home Bridged ERC677 token
* Home Bridged ERC677 token -> Foreign Native ERC20 token
* Home Native ERC20 token -> Foreign Bridged ERC677 token
* Foreign Bridged ERC677 token -> Home Native ERC20 token

## Tokens relay: successful path

### Foreign Native ERC20 token -> Home Bridged ERC677 token

The scenario to pass ERC20 tokens to another side of the bridge in form of ERC677 compatible tokens locks the tokens on the mediator contract on originating (Foreign) bridge side.
On the first operation with some particular ERC20 token, a new ERC677 token contract is deployed on the terminating (Home) bridge side.
Then the mediator on the terminating (Home) bridge side mints some amount of ERC677 tokens.

It is necessary to note that the mediator on the Home side could be configured to use a fee manager.
If so, the amount of minted tokens on the Home side will be less than the actual locked amount on the Foreign side.
Collected fee amount will be distributed between configured reward receivers.

#### Request

In order to initiate the request the ERC20 tokens can be sent using two different ways:
- If the token support ERC677 standard, using one transaction with `transfer` or `transferAndCall` functions.
- Using two transactions: first call `approve` on the token contract, then call any overload of `relayTokens` function.

First transfer of any ERC20 token:
```=
>>Mediator
ForeignOmnibridge::onTokenTransfer/relayTokens
..ForeignOmnibridge::bridgeSpecificActionsOnTokenTransfer
....TokensBridgeLimits::isTokenRegistered -> false
....TokenReader::readDecimals
....TokensBridgeLimits::_initializeTokenBridgeLimits
....TokensBridgeLimits::withinLimit
....TokensBridgeLimits::addTotalSpentPerDay
....BasicOmnibridge::_prepareMessage
......TokenReader::readName
......TokenReader::readSymbol
......MediatorBalanceStorage::_setMediatorBalance
>>Bridge
....MessageDelivery::requireToPassMessage
......ForeignAMB::emitEventOnMessageRequest
........emit UserRequestForAffirmation
>>Mediator
....BasicOmnibridge::_recordBridgeOperation
......BridgeOperationsStorage::setMessageToken
......BridgeOperationsStorage::setMessageRecipient
......BridgeOperationsStorage::setMessageValue
......NativeTokensRegistry::_setTokenRegistrationMessageId
......emit TokensBridgingInitiated
```

Subsequent ERC20 transfers:
```=
>>Mediator
ForeignOmnibridge::onTokenTransfer/relayTokens
..ForeignOmnibridge::bridgeSpecificActionsOnTokenTransfer
....TokensBridgeLimits::isTokenRegistered -> true
....NativeTokensRegistry::isRegisteredAsNativeToken -> false
....TokensBridgeLimits::withinLimit
....TokensBridgeLimits::addTotalSpentPerDay
....BasicOmnibridge::_prepareMessage
......MediatorBalanceStorage::_setMediatorBalance
>>Bridge
....MessageDelivery::requireToPassMessage
......ForeignAMB::emitEventOnMessageRequest
........emit UserRequestForAffirmation
>>Mediator
....BasicOmnibridge::_recordBridgeOperation
......BridgeOperationsStorage::setMessageToken
......BridgeOperationsStorage::setMessageRecipient
......BridgeOperationsStorage::setMessageValue
......emit TokensBridgingInitiated
..
```

#### Execution

First transfer of any ERC20 token:
```=
>>Bridge
BasicHomeAMB::executeAffirmation
..BasicHomeAMB::handleMessage
....ArbitraryMessage::unpackData
....MessageProcessor::processMessage
......MessageProcessor::_passMessage
........MessageProcessor::setMessageSender
........MessageProcessor::setMessageId
>>Mediator
........BasicOmnibridge::deployAndHandleBridgedTokens
..........HomeOmnibridge::_transformName
..........TokenFactory::deploy
..........BasicOmnibridge::_setTokenAddressPair
..........TokensBridgeLimits::_initializeTokenBridgeLimits
..........HomeOmnibridge::_handleTokens
............TokensBridgeLimits::withinExecutionLimit
............TokensBridgeLimits::addTotalExecutedPerDay
............OmnibridgeFeeManagerConnector::_distributeFee
..............OmnibridgeFeeManager::calculateFee
..............IBurnableMintableERC677Token::mint
..............OmnibridgeFeeManager::distributeFee
>>FeeManager
................ERC20::transfer
>>Mediator
............MessageProcessor::messageId
............emit FeeDistributed
............IBurnableMintableERC677Token::mint
............emit TokensBridged
>>Bridge
......MessageProcessor::setMessageCallStatus
......HomeAMB::emitEventOnMessageProcessed
........emit AffirmationCompleted
```

Subsequent ERC20 transfers:
```=
>>Bridge
BasicHomeAMB::executeAffirmation
..BasicHomeAMB::handleMessage
....ArbitraryMessage::unpackData
....MessageProcessor::processMessage
......MessageProcessor::_passMessage
........MessageProcessor::setMessageSender
........MessageProcessor::setMessageId
>>Mediator
........BasicOmnibridge::handleBridgedTokens
..........BridgedTokenRegistry::bridgedTokenAddress
..........TokensBridgeLimits::isTokenRegistered
..........HomeOmnibridge::_handleTokens
............TokensBridgeLimits::withinExecutionLimit
............TokensBridgeLimits::addTotalExecutedPerDay
............OmnibridgeFeeManagerConnector::_distributeFee
..............OmnibridgeFeeManager::calculateFee
..............IBurnableMintableERC677Token::mint
..............OmnibridgeFeeManager::distributeFee
>>FeeManager
................ERC20::transfer
>>Mediator
............MessageProcessor::messageId
............emit FeeDistributed
............IBurnableMintableERC677Token::mint
............emit TokensBridged
>>Bridge
......MessageProcessor::setMessageCallStatus
......HomeAMB::emitEventOnMessageProcessed
........emit AffirmationCompleted
```

### Home Bridged ERC677 token -> Foreign Native ERC20 token

For the scenario to exchange ERC677 tokens back to the locked ERC20 ones, the mediator contract on the originating (Home) bridge side burns the tokens.
The mediator of the terminating bridge side unlocks the ERC20 tokens in favor of the originating request sender.

It is necessary to note that the mediator on the Home side could be configured to use a fee manager.
If so, the amount of unlocked tokens on the Foreign side will be less than the actual burned amount.
Collected fee amount will be distributed between configured reward receivers.

#### Request

Since the token contract is ERC677 compatible, the `transferAndCall` method is used to initiate the exchange from ERC677 tokens to ERC20 tokens.
However, the way of first approving tokens and then calling `relayTokens` also works.

```=
>>Mediator
HomeOmnibridge::onTokenTransfer/relayTokens
..HomeOmnibridge::bridgeSpecificActionsOnTokenTransfer
....TokensBridgeLimits::isTokenRegistered -> true
....NativeTokensRegistry::isRegisteredAsNativeToken -> false
....TokensBridgeLimits::withinLimit
....TokensBridgeLimits::addTotalSpentPerDay
....HomeOmnibridgeFeeManager::isRewardAddress
....OmnibridgeFeeManagerConnector::_distributeFee
......OmnibridgeFeeManager::calculateFee
......ERC20::transfer
......OmnibridgeFeeManager::distributeFee
>>FeeManager
........ERC20::transfer
>>Mediator
....BasicOmnibridge::_prepareMessage
......IBurnableMintableERC677Token::burn
....HomeOmnibridge::_passMessage
......MultiTokenForwardingRulesConnector::_isOracleDrivenLaneAllowed
........MultiTokenForwardingRulesManager::destinationLane
>>Bridge
......MessageDelivery::requireToPassMessage/requireToConfirmMessage
........HomeAMB::emitEventOnMessageRequest
..........emit UserRequestForSignature
>>Mediator
....BasicOmnibridge::_recordBridgeOperation
......BridgeOperationsStorage::setMessageToken
......BridgeOperationsStorage::setMessageRecipient
......BridgeOperationsStorage::setMessageValue
......emit TokensBridgingInitiated
....emit FeeDistributed
```

#### Execution

```=
>>Bridge
BasicForeignAMB::executeSignatures
..ArbitraryMessage.unpackData
....MessageProcessor::processMessage
......MessageProcessor::_passMessage
........MessageProcessor::setMessageSender
........MessageProcessor::setMessageId
>>Mediator
........BasicOmnibridge::handleNativeTokens
..........NativeTokensRegistry::isRegisteredAsNativeToken -> true
..........ForeignOmnibridge::_handleTokens
............TokensBridgeLimits::withinExecutionLimit
............TokensBridgeLimits::addTotalExecutedPerDay
............SafeERC20::safeTransfer
............MediatorBalanceStorage::_setMediatorBalance
............MessageProcessor::messageId
............emit TokensBridged
>>Bridge
......MessageProcessor::setMessageCallStatus
......ForeignAMB::emitEventOnMessageProcessed
........emit RelayedMessage
```

### Home Native ERC20 token -> Foreign Bridged ERC677 token

The scenario to pass ERC20 tokens to another side of the bridge in form of ERC677 compatible tokens locks the tokens on the mediator contract on originating (Home) bridge side.
On the first operation with some particular ERC20 token, a new ERC677 token contract is deployed on the terminating (Foreign) bridge side.
Then the mediator on the terminating (Foreign) bridge side mints some amount of ERC677 tokens.

It is necessary to note that the mediator on the Home side could be configured to use a fee manager.
If so, the amount of locked tokens on the Home side will be higher than the actual minted amount on the Foreign side.
Collected fee amount will be distributed between configured reward receivers.

#### Request

In order to initiate the request the ERC20 tokens can be sent using two different ways:
- If the token support ERC677 standard, using one transaction with `transfer` or `transferAndCall` functions.
- Using two transactions: first call `approve` on the token contract, then call any overload of `relayTokens` function.

First transfer of any ERC20 token:
```=
>>Mediator
HomeOmnibridge::onTokenTransfer/relayTokens
..HomeOmnibridge::bridgeSpecificActionsOnTokenTransfer
....TokensBridgeLimits::isTokenRegistered -> false
....TokenReader::readDecimals
....TokensBridgeLimits::_initializeTokenBridgeLimits
....TokensBridgeLimits::withinLimit
....TokensBridgeLimits::addTotalSpentPerDay
....HomeOmnibridgeFeeManager::isRewardAddress
....OmnibridgeFeeManagerConnector::_distributeFee
......OmnibridgeFeeManager::calculateFee
......SafeERC20::transfer
......OmnibridgeFeeManager::distributeFee
>>FeeManager
........ERC20::transfer
>>Mediator
....BasicOmnibridge::_prepareMessage
......TokenReader::readName
......TokenReader::readSymbol
......MediatorBalanceStorage::_setMediatorBalance
>>Bridge
....MessageDelivery::requireToPassMessage
......ForeignAMB::emitEventOnMessageRequest
........emit UserRequestForSignature
>>Mediator
....BasicOmnibridge::_recordBridgeOperation
......BridgeOperationsStorage::setMessageToken
......BridgeOperationsStorage::setMessageRecipient
......BridgeOperationsStorage::setMessageValue
......NativeTokensRegistry::_setTokenRegistrationMessageId
......emit TokensBridgingInitiated
```

Subsequent ERC20 transfers:
```=
>>Mediator
HomeOmnibridge::onTokenTransfer/relayTokens
..HomeOmnibridge::bridgeSpecificActionsOnTokenTransfer
....TokensBridgeLimits::isTokenRegistered -> true
....NativeTokensRegistry::isRegisteredAsNativeToken -> true
....TokensBridgeLimits::withinLimit
....TokensBridgeLimits::addTotalSpentPerDay
....HomeOmnibridgeFeeManager::isRewardAddress
....OmnibridgeFeeManagerConnector::_distributeFee
......OmnibridgeFeeManager::calculateFee
......SafeERC20::transfer
......OmnibridgeFeeManager::distributeFee
>>FeeManager
........ERC20::transfer
>>Mediator
....BasicOmnibridge::_prepareMessage
......MediatorBalanceStorage::_setMediatorBalance
>>Bridge
....MessageDelivery::requireToPassMessage
......ForeignAMB::emitEventOnMessageRequest
........emit UserRequestForSignature
>>Mediator
....BasicOmnibridge::_recordBridgeOperation
......BridgeOperationsStorage::setMessageToken
......BridgeOperationsStorage::setMessageRecipient
......BridgeOperationsStorage::setMessageValue
......emit TokensBridgingInitiated
..
```

#### Execution

First transfer of any ERC20 token:
```=
>>Bridge
BasicForeignAMB::executeSignatures
..ArbitraryMessage.unpackData
....MessageProcessor::processMessage
......MessageProcessor::_passMessage
........MessageProcessor::setMessageSender
........MessageProcessor::setMessageId
>>Mediator
........BasicOmnibridge::deployAndHandleBridgedTokens
..........ForeignOmnibridge::_transformName
..........TokenFactory::deploy
..........BasicOmnibridge::_setTokenAddressPair
..........TokensBridgeLimits::_initializeTokenBridgeLimits
..........ForeignOmnibridge::_handleTokens
............TokensBridgeLimits::withinExecutionLimit
............TokensBridgeLimits::addTotalExecutedPerDay
............IBurnableMintableERC677Token::mint
............MessageProcessor::messageId
............emit TokensBridged
>>Bridge
......MessageProcessor::setMessageCallStatus
......ForeignAMB::emitEventOnMessageProcessed
........emit RelayedMessage
```

Subsequent ERC20 transfers:
```=
>>Bridge
BasicForeignAMB::executeSignatures
..ArbitraryMessage.unpackData
....MessageProcessor::processMessage
......MessageProcessor::_passMessage
........MessageProcessor::setMessageSender
........MessageProcessor::setMessageId
>>Mediator
........BasicOmnibridge::handleBridgedTokens
..........BridgedTokenRegistry::bridgedTokenAddress
..........TokensBridgeLimits::isTokenRegistered
..........ForeignOmnibridge::_handleTokens
............TokensBridgeLimits::withinExecutionLimit
............TokensBridgeLimits::addTotalExecutedPerDay
............IBurnableMintableERC677Token::mint
............MessageProcessor::messageId
............emit TokensBridged
>>Bridge
......MessageProcessor::setMessageCallStatus
......ForeignAMB::emitEventOnMessageProcessed
........emit RelayedMessage
```

### Foreign Bridged ERC677 token -> Home Native ERC20 token

For the scenario to exchange ERC677 tokens back to the locked ERC20 ones, the mediator contract on the originating (Foreign) bridge side burns the tokens.
The mediator of the terminating bridge side unlocks the ERC20 tokens in favor of the originating request sender.

It is necessary to note that the mediator on the Home side could be configured to use a fee manager.
If so, the amount of unlocked tokens on the Foreign side will be less than the actual burned amount.
Collected fee amount will be distributed between configured reward receivers.

#### Request

Since the token contract is ERC677 compatible, the `transferAndCall` method is used to initiate the exchange from ERC677 tokens to ERC20 tokens.
However, the way of first approving tokens and then calling `relayTokens` also works.

```=
>>Mediator
ForeignOmnibridge::onTokenTransfer/relayTokens
..ForeignOmnibridge::bridgeSpecificActionsOnTokenTransfer
....TokensBridgeLimits::isTokenRegistered -> true
....NativeTokensRegistry::isRegisteredAsNativeToken -> false
....TokensBridgeLimits::withinLimit
....TokensBridgeLimits::addTotalSpentPerDay
....BasicOmnibridge::_prepareMessage
......IBurnableMintableERC677Token::burn
>>Bridge
....MessageDelivery::requireToPassMessage
......ForeignAMB::emitEventOnMessageRequest
........emit UserRequestForAffirmation
>>Mediator
....BasicOmnibridge::_recordBridgeOperation
......BridgeOperationsStorage::setMessageToken
......BridgeOperationsStorage::setMessageRecipient
......BridgeOperationsStorage::setMessageValue
......emit TokensBridgingInitiated
```

#### Execution

```=
>>Bridge
BasicHomeAMB::executeAffirmation
..BasicHomeAMB::handleMessage
....ArbitraryMessage::unpackData
....MessageProcessor::processMessage
......MessageProcessor::_passMessage
........MessageProcessor::setMessageSender
........MessageProcessor::setMessageId
>>Mediator
........BasicOmnibridge::handleNativeTokens
..........NativeTokensRegistry::isRegisteredAsNativeToken -> true
..........HomeOmnibridge::_handleTokens
............TokensBridgeLimits::withinExecutionLimit
............TokensBridgeLimits::addTotalExecutedPerDay
............OmnibridgeFeeManagerConnector::_distributeFee
..............OmnibridgeFeeManager::calculateFee
..............SafeERC20::safeTransfer
..............OmnibridgeFeeManager::distributeFee
>>FeeManager
................ERC20::transfer
>>Mediator
............MessageProcessor::messageId
............emit FeeDistributed
............SafeERC20::safeTransfer
............MediatorBalanceStorage::_setMediatorBalance
............emit TokensBridged
>>Bridge
......MessageProcessor::setMessageCallStatus
......HomeAMB::emitEventOnMessageProcessed
........emit AffirmationCompleted
```

## Tokens relay: failure and recovery

Failures in the mediator contract at the moment to complete a relay operation could cause imbalance of the extension due to the asynchronous nature of the Arbitrary Message Bridge.
Therefore the feature to recover the balance of the MULTI-AMB-ERC20-TO-ERC677 extension is very important for the extension healthiness. 

For the mediator contracts there is a possibility to provide a way how to recover an operation if the data relay request has been failed within the mediator contract on another side.

For the token bridging this means that:
  * if the operation to mint tokens as part of the Foreign->Home request processing failed, it is possible to unlock the tokens on the Foreign side;
  * if the operation to unlock tokens as part of the Home->Foreign request processing failed, it is possible to mint the burnt tokens on the Home side;
  * if the operation to mint tokens as part of the Home->Foreign request processing failed, it is possible to unlock the tokens on the Home side;
  * if the operation to unlock tokens as part of the Foreign->Home request processing failed, it is possible to mint the burnt tokens on the Foreign side.

The mediator can get the status of the corresponding relay request from the bridge contract by using the id of this request (AMB message id).
So, as soon as a user would like to perform a recovery they send a call with the request id to the mediator contract and if such request was failed indeed, the mediator originates the recovery message to the mediator on another side.
The recovery messages contain the same information as it was used by the tokens relay request, so the terminating mediator checks that such request was registered and executes the actual recovery by using amount of tokens from the request and the request sender.

It is important that the recovery must be performed without the extension admin attendance.

### Failed attempt to relay tokens from Home to Foreign

#### Execution Failure

A failure happens within the message handler on the mediator contract's side when the Foreign bridge contract passes the message to it.

```=
>>Bridge
BasicForeignAMB::executeSignatures
..ArbitraryMessage.unpackData
....MessageProcessor::processMessage
......MessageProcessor::_passMessage
........MessageProcessor::setMessageSender
........MessageProcessor::setMessageId
>>Mediator
........[failed ForeignOmnibridge::deployAndHandleBridgedTokens/handleBridgedTokens/handleNativeTokens]
>>Bridge
......MessageProcessor::setMessageCallStatus
......MessageProcessor::setFailedMessageReceiver
......MessageProcessor::setFailedMessageSender
......ForeignAMB::emitEventOnMessageProcessed
........emit RelayedMessage
```

#### Recovery initialization

As soon as a user identified a message transfer failure (e.g. the corresponding amount tokens did not appear on the user account balance on the Foreign chain), they call the `requestFailedMessageFix` method on the Foreign mediator contract.
Anyone is able to call this method by specifying the message id.
The method requests the bridge contract whether the corresponding message has failed indeed.
That is why the operation is safe to perform by anyone.

```=
>>Mediator
FailedMessagesProcessor::requestFailedMessageFix
>>Bridge
..MessageProcessor::messageCallStatus
..MessageProcessor::failedMessageReceiver
..MessageProcessor::failedMessageSender
..MessageDelivery::requireToPassMessage
....ForeignAMB::emitEventOnMessageRequest
......emit UserRequestForAffirmation
```

#### Recovery completion

The Home chain initially originated the request, that is why the extension is imbalanced - there are more tokens on the Foreign side than tokens on the Home side.
Therefore, the appeared message to invoke `fixFailedMessage` causes minting/unlock of the tokens.

```=
>>Bridge
BasicHomeAMB::executeAffirmation
..BasicHomeAMB::handleMessage
....ArbitraryMessage::unpackData
....MessageProcessor::processMessage
......MessageProcessor::_passMessage
........MessageProcessor::setMessageSender
........MessageProcessor::setMessageId
>>Mediator
........FailedMessagesProcessor::fixFailedMessage
..........MultiTokenBridgeMediator::messageToken
..........MultiTokenBridgeMediator::messageRecipient
..........MultiTokenBridgeMediator::messageValue
..........MultiTokenBridgeMediator::setMessageFixed
..........BasicOmnibridge::executeActionOnFixedTokens
............NativeTokensRegistry::tokenRegistrationMessageId
............SafeERC20::safeTransfer/IBurnableMintableERC677Token::mint
..............<######>
..........emit FailedMessageFixed
>>Bridge
......MessageProcessor::setMessageCallStatus
......HomeAMB::emitEventOnMessageProcessed
........emit AffirmationCompleted
```

### Failed attempt to relay tokens from Foreign to Home

#### Execution Failure

A failure happens within the message handler on the mediator contract's side when the Home bridge contract passes the message to it.

```=
>>Bridge
BasicHomeAMB::executeAffirmation
..BasicHomeAMB::handleMessage
....ArbitraryMessage::unpackData
....MessageProcessor::processMessage
......MessageProcessor::_passMessage
........MessageProcessor::setMessageSender
........MessageProcessor::setMessageId
>>Mediator
........[failed HomeOmnibridge::deployAndHandleBridgedTokens/handleBridgedTokens/handleNativeTokens]
>>Bridge
......MessageProcessor::setMessageCallStatus
......MessageProcessor::setFailedMessageReceiver
......MessageProcessor::setFailedMessageSender
......HomeAMB::emitEventOnMessageProcessed
........emit AffirmationCompleted
```

#### Recovery initialization

As soon as a user identified a message transfer failure (e.g. the corresponding amount of tokens did not appear on the user account balance on the Home chain), they call the `requestFailedMessageFix` method on the Home mediator contract.
Anyone is able to call this method by specifying the message id.
The method requests the bridge contract whether the corresponding message has failed indeed.
That is why the operation is safe to perform by anyone.

```=
>>Mediator
FailedMessagesProcessor::requestFailedMessageFix
>>Bridge
..MessageProcessor::messageCallStatus
..MessageProcessor::failedMessageReceiver
..MessageProcessor::failedMessageSender
..MessageDelivery::requireToPassMessage
....HomeAMB::emitEventOnMessageRequest
......emit UserRequestForSignature
```

#### Recovery completion

The Foreign chain initially originated the request, that is why the extension is imbalanced - there are more tokens on the Home side than tokens on the Foreign side. 
Therefore, the appeared message to invoke `fixFailedMessage` causes minting/unlock of the tokens.

```=
>>Bridge
BasicForeignAMB::executeSignatures
..ArbitraryMessage.unpackData
....MessageProcessor::processMessage
......MessageProcessor::_passMessage
........MessageProcessor::setMessageSender
........MessageProcessor::setMessageId
>>Mediator
........FailedMessagesProcessor::fixFailedMessage
..........MultiTokenBridgeMediator::messageToken
..........MultiTokenBridgeMediator::messageRecipient
..........MultiTokenBridgeMediator::messageValue
..........BasicOmnibridge::executeActionOnFixedTokens
............NativeTokensRegistry::tokenRegistrationMessageId
............SafeERC20::safeTransfer/IBurnableMintableERC677Token::mint
..............<######>
..........emit FailedMessageFixed
>>Bridge
......MessageProcessor::setMessageCallStatus
......ForeignAMB::emitEventOnMessageProcessed
........emit RelayedMessage
```

## Tokens relay to an alternative receiver

The idea of the feature is that a user invokes a special method (`relayTokens`) on the mediator contract in order to specify the receiver of the tokens on the another side.
So, the tokens will be unlocked/minted in favor of specified account rather than the request originator as it is assumed by the general approach. 

Also, the alternative receiver can be specified using data field when using `transferAndCall`.
All deployed bridged tokens on both sides has a support of `transferAndCall` function.
Existing native tokens might also have such support, please check the implementation of the specific token.
