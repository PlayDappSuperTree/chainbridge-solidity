/**
 * Copyright 2020 ChainSafe Systems
 * SPDX-License-Identifier: LGPL-3.0-only
 */
const Ethers = require('ethers');

const Helpers = require('../../helpers');

const BridgeContract = artifacts.require("Bridge");
const ERC721MintableContract = artifacts.require("ERC721MinterBurnerPauser");
const ERC721HandlerContract = artifacts.require("ERC721Handler");

contract('ERC721Handler - [Deposit ERC721]', async (accounts) => {
    const relayerThreshold = 2;
    const chainID = 1;
    const expectedDepositNonce = 1;
    const depositerAddress = accounts[1];
    const tokenID = 1;

    let BridgeInstance;
    let ERC721MintableInstance;
    let ERC721HandlerInstance;

    let resourceID;
    let initialResourceIDs;
    let initialContractAddresses;
    let burnableContractAddresses;

    beforeEach(async () => {
        // await Promise.all([
        //     BridgeContract.new(chainID, [], relayerThreshold, 0, 100).then(instance => BridgeInstance = instance),
        //     ERC721MintableContract.new("token", "TOK", "").then(instance => ERC721MintableInstance = instance)
        // ])

        BridgeInstance = await BridgeContract.new(chainID, [], relayerThreshold, 0, 100);
        ERC721MintableInstance = await ERC721MintableContract.new("token", "TOK", "");


        resourceID = Helpers.createResourceID(ERC721MintableInstance.address, chainID);
        initialResourceIDs = [resourceID];
        initialContractAddresses = [ERC721MintableInstance.address];
        burnableContractAddresses = []

        // await Promise.all([
        //     ERC721HandlerContract.new(BridgeInstance.address, initialResourceIDs, initialContractAddresses, burnableContractAddresses).then(instance => ERC721HandlerInstance = instance),
        //     ERC721MintableInstance.mint(depositerAddress, tokenID, "")
        // ]);

        ERC721HandlerInstance = await ERC721HandlerContract.new(BridgeInstance.address, initialResourceIDs, initialContractAddresses, burnableContractAddresses);
        await ERC721MintableInstance.mint(depositerAddress, tokenID, "");

        // await Promise.all([
        //     ERC721MintableInstance.approve(ERC721HandlerInstance.address, tokenID, { from: depositerAddress }),
        //     BridgeInstance.adminSetResource(ERC721HandlerInstance.address, resourceID, ERC721MintableInstance.address)
        // ]);

        await ERC721MintableInstance.approve(ERC721HandlerInstance.address, tokenID, { from: depositerAddress });
        await BridgeInstance.adminSetResource(ERC721HandlerInstance.address, resourceID, ERC721MintableInstance.address);

    });

    it('[sanity] depositer owns ERC721 with tokenID', async () => {
        const tokenOwner = await ERC721MintableInstance.ownerOf(tokenID);
        assert.equal(depositerAddress, tokenOwner);
    });

    it('[sanity] ERC721HandlerInstance.address has an allowance for tokenID', async () => {
        const tokenAllowee = await ERC721MintableInstance.getApproved(tokenID);
        assert.equal(ERC721HandlerInstance.address, tokenAllowee);
    });


});
