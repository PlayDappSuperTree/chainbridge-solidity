/**
 * Copyright 2020 ChainSafe Systems
 * SPDX-License-Identifier: LGPL-3.0-only
 */
const TruffleAssert = require('truffle-assertions');
const Ethers = require('ethers');
const Helpers = require('../helpers');
const BridgeContract = artifacts.require("Bridge");
const ERC20MintableContract = artifacts.require("ERC20PresetMinterPauser");
const ERC20HandlerContract = artifacts.require("ERC20Handler");
const ERC721HandlerContract = artifacts.require("ERC721Handler");
const ERC721MintableContract = artifacts.require("ERC721MinterBurnerPauser");
const GenericHandlerContract = artifacts.require('GenericHandler');
const CentrifugeAssetContract = artifacts.require("CentrifugeAsset");
const TestERC721ReceiverContract = artifacts.require("TestERC721Receiver");

// This test does NOT include all getter methods, just
// getters that should work with only the constructor called
contract('Bridge - [admin]', async accounts => {
    const chainID = 1;
    const initialRelayers = accounts.slice(0, 3);
    const initialRelayerThreshold = 2;

    const expectedBridgeAdmin = accounts[0];
    let ADMIN_ROLE;

    let BridgeInstance;

    beforeEach(async () => {
        BridgeInstance = await BridgeContract.new(chainID, initialRelayers, initialRelayerThreshold, 0, 100);
        ADMIN_ROLE = await BridgeInstance.DEFAULT_ADMIN_ROLE()
    });

    // Check chiainID of the bridge
    it('check chainId of the bridge', async () => {
        assert.equal(await BridgeInstance.getChainId(), chainID);
    });

    // Testing pausable methods

    it('Bridge should not be paused', async () => {
        assert.isFalse(await BridgeInstance.paused());
    });

    it('Bridge should be paused', async () => {
        TruffleAssert.passes(await BridgeInstance.adminPauseTransfers());
        assert.isTrue(await BridgeInstance.paused());
    });

    it('Bridge should be unpaused after being paused', async () => {
        TruffleAssert.passes(await BridgeInstance.adminPauseTransfers());
        assert.isTrue(await BridgeInstance.paused());
        TruffleAssert.passes(await BridgeInstance.adminUnpauseTransfers());
        assert.isFalse(await BridgeInstance.paused());
    });

    // Testing relayer methods

    it('_relayerThreshold should be initialRelayerThreshold', async () => {
        assert.equal(await BridgeInstance._relayerThreshold.call(), initialRelayerThreshold);
    });

    it('_relayerThreshold should be initialRelayerThreshold', async () => {
        const newRelayerThreshold = 1;
        TruffleAssert.passes(await BridgeInstance.adminChangeRelayerThreshold(newRelayerThreshold));
        assert.equal(await BridgeInstance._relayerThreshold.call(), newRelayerThreshold);
    });

    it('newRelayer should be added as a relayer', async () => {
        const newRelayer = accounts[4];
        TruffleAssert.passes(await BridgeInstance.adminAddRelayer(newRelayer));
        assert.isTrue(await BridgeInstance.isRelayer(newRelayer));
    });

    it('newRelayer should be removed as a relayer after being added', async () => {
        const newRelayer = accounts[4];
        TruffleAssert.passes(await BridgeInstance.adminAddRelayer(newRelayer));
        assert.isTrue(await BridgeInstance.isRelayer(newRelayer))
        TruffleAssert.passes(await BridgeInstance.adminRemoveRelayer(newRelayer));
        assert.isFalse(await BridgeInstance.isRelayer(newRelayer));
    });

    it('existingRelayer should not be able to be added as a relayer', async () => {
        const existingRelayer = accounts[1];
        await TruffleAssert.reverts(BridgeInstance.adminAddRelayer(existingRelayer));
        assert.isTrue(await BridgeInstance.isRelayer(existingRelayer));
    });

    it('nonRelayerAddr should not be able to be added as a relayer', async () => {
        const nonRelayerAddr = accounts[4];
        await TruffleAssert.reverts(BridgeInstance.adminRemoveRelayer(nonRelayerAddr));
        assert.isFalse(await BridgeInstance.isRelayer(nonRelayerAddr));
    });

    // Testing ownership methods

    it('Bridge admin should be expectedBridgeAdmin', async () => {
        assert.isTrue(await BridgeInstance.hasRole(ADMIN_ROLE, expectedBridgeAdmin));
    });

    it('Bridge admin should be changed to expectedBridgeAdmin', async () => {
        assert.isTrue(await BridgeInstance.hasRole(ADMIN_ROLE, accounts[0]));
        //cant not renounce admin anymore
        TruffleAssert.reverts(BridgeInstance.renounceRole(ADMIN_ROLE, accounts[0]));

        const expectedBridgeAdmin2 = accounts[1];
        TruffleAssert.passes(await BridgeInstance.grantRole(ADMIN_ROLE, expectedBridgeAdmin2));

        //new new account has admin role
        assert.isTrue(await BridgeInstance.hasRole(ADMIN_ROLE, expectedBridgeAdmin2));
        await BridgeInstance.revokeRole(ADMIN_ROLE, accounts[0]);

        //old admin is not admin anymore
        assert.isFalse(await BridgeInstance.hasRole(ADMIN_ROLE, accounts[0]));

    });

    // Set Handler Address

    it('Should set a Resource ID for handler address', async () => {
        const ERC20MintableInstance = await ERC20MintableContract.new("token", "TOK");
        const resourceID = Helpers.createResourceID(ERC20MintableInstance.address, chainID);
        const ERC20HandlerInstance = await ERC20HandlerContract.new(BridgeInstance.address, [], [], []);
        assert.equal(await BridgeInstance._resourceIDToHandlerAddress.call(resourceID), Ethers.constants.AddressZero);
        TruffleAssert.passes(await BridgeInstance.adminSetResource(ERC20HandlerInstance.address, resourceID, ERC20MintableInstance.address));
        assert.equal(await BridgeInstance._resourceIDToHandlerAddress.call(resourceID), ERC20HandlerInstance.address);
    });


    // Set resource ID

    it('Should set a ERC20 Resource ID and contract address', async () => {
        const ERC20MintableInstance = await ERC20MintableContract.new("token", "TOK");
        const resourceID = Helpers.createResourceID(ERC20MintableInstance.address, chainID);
        const ERC20HandlerInstance = await ERC20HandlerContract.new(BridgeInstance.address, [], [], []);

        TruffleAssert.passes(await BridgeInstance.adminSetResource(
            ERC20HandlerInstance.address, resourceID, ERC20MintableInstance.address));
        assert.equal(await ERC20HandlerInstance._resourceIDToTokenContractAddress.call(resourceID), ERC20MintableInstance.address);
        assert.equal(await ERC20HandlerInstance._tokenContractAddressToResourceID.call(ERC20MintableInstance.address), resourceID.toLowerCase());
    });

    // Set Generic Resource

    it('Should set a Generic Resource ID and contract address', async () => {
        const CentrifugeAssetInstance = await CentrifugeAssetContract.new();
        const resourceID = Helpers.createResourceID(CentrifugeAssetInstance.address, chainID);
        const GenericHandlerInstance = await GenericHandlerContract.new(BridgeInstance.address, [], [], [], []);

        TruffleAssert.passes(await BridgeInstance.adminSetGenericResource(GenericHandlerInstance.address, resourceID, CentrifugeAssetInstance.address, '0x00000000', '0x00000000'));
        assert.equal(await GenericHandlerInstance._resourceIDToContractAddress.call(resourceID), CentrifugeAssetInstance.address);
        assert.equal(await GenericHandlerInstance._contractAddressToResourceID.call(CentrifugeAssetInstance.address), resourceID.toLowerCase());
    });

    // Set burnable

    it('Should set ERC20MintableInstance.address as burnable', async () => {
        const ERC20MintableInstance = await ERC20MintableContract.new("token", "TOK");
        const resourceID = Helpers.createResourceID(ERC20MintableInstance.address, chainID);
        const ERC20HandlerInstance = await ERC20HandlerContract.new(BridgeInstance.address, [resourceID], [ERC20MintableInstance.address], []);

        TruffleAssert.passes(await BridgeInstance.adminSetBurnable(ERC20HandlerInstance.address, ERC20MintableInstance.address));
        assert.isTrue(await ERC20HandlerInstance._burnList.call(ERC20MintableInstance.address));
    });

    // Set fee

    it('Should set fee', async () => {
        assert.equal(await BridgeInstance._fee.call(), 0);

        const fee = Ethers.utils.parseEther("0.05");
        await BridgeInstance.adminChangeFee(fee);
        const newFee = await BridgeInstance._fee.call()
        assert.equal(web3.utils.fromWei(newFee, "ether"), "0.05")
    });


    it('extra', async () => {
        const ERC20MintableInstance = await ERC20MintableContract.new("token", "TOK");
        const resourceID = Helpers.createResourceID(ERC20MintableInstance.address, chainID);
        const ERC20HandlerInstance = await ERC20HandlerContract.new(BridgeInstance.address, [], [], []);


        await ERC20MintableInstance.mint(accounts[0], 100);

        await ERC20MintableInstance.approve(ERC20HandlerInstance.address, 50);

        const ERC721MintableInstance = await ERC721MintableContract.new("NFTtoken", "NFT", "1111");
        const resourceID2 = Helpers.createResourceID(ERC721MintableInstance.address, chainID);
        const ERC721HandlerInstance = await ERC721HandlerContract.new(BridgeInstance.address, [], [], []);

        const TestERC721ReceiverInstance = await TestERC721ReceiverContract.new();
        await ERC721MintableInstance.grantRole(await ERC721MintableInstance.MINTER_ROLE(), ERC721HandlerInstance.address);

        // await ERC721HandlerInstance.publicMintERC721(ERC721MintableInstance.address, TestERC721ReceiverInstance.address, 1, "0x0");
        // await ERC721HandlerInstance.publicMintERC721(ERC721MintableInstance.address, accounts[0], 2, "0x0");
        //await ERC721HandlerInstance.publicMintERC721(ERC721MintableInstance.address, ERC20HandlerInstance.address, 1, "0x0");


    });


    // Withdraw

    // it('Should withdraw funds', async () => {
    //     const numTokens = 10;
    //     const tokenOwner = accounts[0];
    //
    //     let ownerBalance;
    //     let handlerBalance;
    //
    //     const ERC20MintableInstance = await ERC20MintableContract.new("token", "TOK");
    //     const resourceID = Helpers.createResourceID(ERC20MintableInstance.address, chainID);
    //     const ERC20HandlerInstance = await ERC20HandlerContract.new(BridgeInstance.address, [resourceID], [ERC20MintableInstance.address], []);
    //
    //     await ERC20MintableInstance.mint(tokenOwner, numTokens);
    //     ownerBalance = await ERC20MintableInstance.balanceOf(tokenOwner);
    //     assert.equal(ownerBalance, numTokens);
    //
    //     await ERC20MintableInstance.transfer(ERC20HandlerInstance.address, numTokens);
    //     ownerBalance = await ERC20MintableInstance.balanceOf(tokenOwner);
    //     assert.equal(ownerBalance, 0);
    //     handlerBalance = await ERC20MintableInstance.balanceOf(ERC20HandlerInstance.address);
    //     assert.equal(handlerBalance, numTokens);
    //
    //
    // });
});
