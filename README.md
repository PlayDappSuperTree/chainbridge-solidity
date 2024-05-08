# folked from  https://github.com/ChainSafe/chainbridge-solidity

This repository is folked from https://github.com/ChainSafe/chainbridge-solidity and modified to support briging between ERC20 on ethereum network and native Ethereum token on avalanche subnet.


# chainbridge-solidity

ChainBridge uses Solidity smart contracts to enable transfers to and from EVM compatible chains. These contracts consist of a core bridge contract (Bridge.sol) and a set of handler contracts (ERC20Handler.sol, ERC721Handler.sol, and GenericHandler.sol). The bridge contract is responsible for initiating, voting on, and executing proposed transfers. The handlers are used by the bridge contract to interact with other existing contracts.

Read more [here](https://chainbridge.chainsafe.io/).

A CLI to deploy and interact with these contracts can be found [here](https://github.com/ChainSafe/chainbridge-deploy/tree/master/cb-sol-cli).

## Dependencies

Requires `nodejs` and `npm`.

## Commands

`make install-deps`: Installs truffle and ganache globally, fetches local dependencies. Also installs `abigen` from `go-ethereum`.

`make bindings`: Creates go bindings in `./build/bindings/go`

`PORT=<port> SILENT=<bool> make start-ganache`: Starts a ganache instance, default `PORT=8545 SILENT=false`

`QUIET=<bool> make start-geth`: Starts a geth instance with test keys

`PORT=<port> make deploy`: Deploys all contract instances, default `PORT=8545`

`make test`: Runs truffle tests.

`make compile`: Compile contracts.

# ChainSafe Security Policy

## Test result
```bash
 Contract: Bridge - [admin]
    ✓ Bridge should not be paused
    ✓ Bridge should be paused (42ms)
    ✓ Bridge should be unpaused after being paused (90ms)
    ✓ _relayerThreshold should be initialRelayerThreshold
    ✓ _relayerThreshold should be initialRelayerThreshold (56ms)
    ✓ newRelayer should be added as a relayer (55ms)
    ✓ newRelayer should be removed as a relayer after being added (135ms)
    ✓ existingRelayer should not be able to be added as a relayer (171ms)
    ✓ nonRelayerAddr should not be able to be added as a relayer (49ms)
    ✓ Bridge admin should be expectedBridgeAdmin
    ✓ Bridge admin should be changed to expectedBridgeAdmin (93ms)
    ✓ Should set a Resource ID for handler address (208ms)
    ✓ Should set a ERC20 Resource ID and contract address (258ms)
    ✓ Should set a Generic Resource ID and contract address (161ms)
    ✓ Should set ERC20MintableInstance.address as burnable (232ms)
    ✓ Should set fee (43ms)
    ✓ extra (656ms)

  Contract: Bridge - [voteProposal with relayerThreshold == 3]
    ✓ [sanity] bridge configured with threshold, relayers, and expiry (58ms)
    ✓ [sanity] depositProposal should be created with expected values (126ms)
    ✓ voting on depositProposal after threshold results in cancelled proposal (248ms)
    ✓ relayer can cancel proposal after threshold blocks have passed (238ms)
    ✓ admin can cancel proposal after threshold blocks have passed (240ms)
    ✓ proposal cannot be cancelled twice (289ms)

  Contract: Bridge - [create a deposit proposal (voteProposal) with relayerThreshold = 1]
    ✓ should create depositProposal successfully (107ms)
    ✓ should revert because depositerAddress is not a relayer
    ✓ depositProposal shouldn't be created if it has an Active status (152ms)
    ✓ getProposal should be called successfully
    ✓ depositProposal should be created with expected values (100ms)
    ✓ originChainRelayerAddress should be marked as voted for proposal (128ms)
    ✓ DepositProposalCreated event should be emitted with expected values (88ms)

  Contract: Bridge - [create a deposit proposal (voteProposal) with relayerThreshold > 1]
    ✓ should create depositProposal successfully (84ms)
    ✓ should revert because depositerAddress is not a relayer
    ✓ depositProposal shouldn't be created if it has an Active status (139ms)
    ✓ depositProposal should be created with expected values (80ms)
    ✓ originChainRelayerAddress should be marked as voted for proposal (118ms)
    ✓ DepositProposalCreated event should be emitted with expected values (100ms)

  Contract: Bridge - [deposit - ERC20]
    ✓ [sanity] test depositerAddress' balance
    ✓ [sanity] test OriginERC20HandlerInstance.address' allowance
    ✓ ERC20 deposit can be made (158ms)
    ✓ _depositCounts should be increments from 0 to 1 (142ms)
    ✓ ERC20 can be deposited with correct balances (149ms)
    ✓ depositRecord is created with expected depositNonce and correct value (137ms)
    ✓ Deposit event is fired with expected value (310ms)

  Contract: Bridge - [deposit - ERC721]
    ✓ [sanity] test depositerAddress' balance
    ✓ [sanity] test depositerAddress owns token with ID: 42
    ✓ [sanity] test OriginERC721HandlerInstance.address' allowance
    ✓ ERC721 deposit can be made (263ms)
    ✓ _depositCounts should be increments from 0 to 1 (239ms)
    ✓ ERC721 can be deposited with correct owner and balances (279ms)
    ✓ ERC721 deposit record is created with expected depositNonce and values (280ms)
    ✓ Deposit event is fired with expected value (271ms)

  Contract: Bridge - [voteProposal with relayerThreshold == 3]
    ✓ [sanity] bridge configured with threshold and relayers
    ✓ [sanity] depositProposal should be created with expected values (103ms)
    ✓ should revert because depositerAddress is not a relayer
    ✓ depositProposal shouldn't be voted on if it has a Passed status (254ms)
    ✓ depositProposal shouldn't be voted on if it has a Transferred status (374ms)
    ✓ relayer shouldn't be able to vote on a depositProposal more than once (132ms)
    ✓ Should be able to create a proposal with a different hash (167ms)
    ✓ Relayer's vote should be recorded correctly - yes vote (359ms)
    ✓ Relayer's address should be marked as voted for proposal (117ms)
    ✓ DepositProposalFinalized event should be emitted when proposal status updated to passed after numYes >= relayerThreshold (228ms)
    ✓ DepositProposalVote event fired when proposal vote made (60ms)
    ✓ Execution successful (436ms)

  Contract: E2E ERC20 - Two EVM Chains
    ✓ [sanity] depositerAddress' balance should be equal to initialTokenAmount
    ✓ [sanity] OriginERC20HandlerInstance.address should have an allowance of depositAmount from depositerAddress
    ✓ [sanity] DestinationERC20HandlerInstance.address should have minterRole for DestinationERC20MintableInstance
    ✓ E2E: depositAmount of Origin ERC20 owned by depositAddress to Destination ERC20 owned by recipientAddress and back again (822ms)

  Contract: E2E ERC20 - Same Chain
    ✓ [sanity] depositerAddress' balance should be equal to initialTokenAmount
    ✓ [sanity] ERC20HandlerInstance.address should have an allowance of depositAmount from depositerAddress
    ✓ depositAmount of Destination ERC20 should be transferred to recipientAddress (407ms)

  Contract: E2E ERC721 - Two EVM Chains
    ✓ [sanity] depositerAddress' should own tokenID
    ✓ [sanity] ERC721HandlerInstance.address should have an allowance for tokenID from depositerAddress
    ✓ [sanity] DestinationERC721HandlerInstance.address should have minterRole for DestinationERC721MintableInstance
    ✓ E2E: tokenID of Origin ERC721 owned by depositAddress to Destination ERC721 owned by recipientAddress and back again (2217ms)

  Contract: E2E ERC721 - Same Chain
    ✓ [sanity] depositerAddress' should own tokenID
    ✓ [sanity] ERC721HandlerInstance.address should have an allowance for tokenID from depositerAddress
    ✓ depositAmount of Destination ERC721 should be transferred to recipientAddress (613ms)

  Contract: ERC20Handler - [Burn ERC20]
    ✓ [sanity] contract should be deployed successfully (86ms)
    ✓ burnableContractAddresses should be marked true in _burnList (89ms)
    ✓ ERC20MintableInstance2.address should not be marked true in _burnList (92ms)
    ✓ ERC20MintableInstance2.address should be marked true in _burnList after setBurnable is called (99ms)

  Contract: ERC20Handler - [constructor]
    ✓ [sanity] contract should be deployed successfully (83ms)
    ✓ initialResourceIDs should be parsed correctly and corresponding resourceID mappings should have expected values (123ms)

  Contract: ERC20Handler - [Deposit ERC20]
    ✓ [sanity] depositer owns tokenAmount of ERC20
    ✓ [sanity] ERC20HandlerInstance.address has an allowance of tokenAmount from depositerAddress

  Contract: ERC20Handler - [Deposit Burn ERC20]
    ✓ [sanity] burnableContractAddresses should be marked true in _burnList

  Contract: ERC20Handler - [isWhitelisted]
    ✓ [sanity] contract should be deployed successfully (57ms)
    ✓ initialContractAddress should be whitelisted (53ms)

  Contract: ERC20Handler - [setResourceIDAndContractAddress]
    ✓ [sanity] ERC20MintableInstance1's resourceID and contract address should be set correctly
    ✓ new resourceID and corresponding contract address should be set correctly (161ms)
    ✓ existing resourceID should be updated correctly with new token contract address (407ms)
    ✓ existing resourceID should be updated correctly with new handler address (670ms)
    ✓ existing resourceID should be replaced by new resourceID in handler (532ms)

  Contract: ERC721Handler - [Burn ERC721]
    ✓ [sanity] contract should be deployed successfully (89ms)
    ✓ burnableContractAddresses should be marked true in _burnList (94ms)
    ✓ ERC721MintableInstance2.address should not be marked true in _burnList (68ms)
    ✓ ERC721MintableInstance2.address should be marked true in _burnList after setBurnable is called (125ms)

  Contract: ERC721Handler - [Deposit ERC721]
    ✓ [sanity] depositer owns ERC721 with tokenID
    ✓ [sanity] ERC721HandlerInstance.address has an allowance for tokenID

  Contract: ERC721Handler - [Deposit Burn ERC721]
    ✓ [sanity] burnableContractAddresses should be marked true in _burnList
    ✓ [sanity] ERC721MintableInstance1 tokenID has been minted for depositerAddress
    ✓ depositAmount of ERC721MintableInstance1 tokens should have been burned (284ms)

  102 passing (1m)

```

## Reporting a Security Bug

We take all security issues seriously, if you believe you have found a security issue within a ChainSafe
project please notify us immediately. If an issue is confirmed, we will take all necessary precautions 
to ensure a statement and patch release is made in a timely manner.

Please email us a description of the flaw and any related information (e.g. reproduction steps, version) to
[security at chainsafe dot io](mailto:security@chainsafe.io).


