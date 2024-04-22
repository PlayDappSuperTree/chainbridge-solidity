pragma solidity 0.6.4;
pragma experimental ABIEncoderV2;

import "../interfaces/IGenericHandler.sol";
import "../ERC20Safe.sol";
import "./HandlerHelpers.sol";
import "@openzeppelin/contracts/introspection/ERC165.sol";
import "../interfaces/IERC20Permit.sol";
/**
    @title Handles generic deposits and deposit executions.
    @author ChainSafe Systems.
    @notice This contract is intended to be used with the Bridge contract.
 */
contract GenericERC20NativeHandler is ERC165, IGenericHandler, HandlerHelpers, ERC20Safe {

    struct DepositRecord {
        uint8 _destinationChainID;
        address _depositer;
        bytes32 _resourceID;
        bytes _metaData;
    }

    // depositNonce => Deposit Record
    mapping(uint8 => mapping(uint64 => DepositRecord)) public _depositRecords;

    // resourceID => contract address
    mapping(bytes32 => address) public _resourceIDToContractAddress;

    // contract address => resourceID
    mapping(address => bytes32) public _contractAddressToResourceID;

    // contract address => deposit function signature
    mapping(address => bytes4) public _contractAddressToDepositFunctionSignature;

    // contract address => execute proposal function signature
    mapping(address => bytes4) public _contractAddressToExecuteFunctionSignature;

    /**
        @param bridgeAddress Contract address of previously deployed Bridge.
        @param initialResourceIDs Resource IDs used to identify a specific contract address.
        These are the Resource IDs this contract will initially support.
        @param initialContractAddresses These are the addresses the {initialResourceIDs} will point to, and are the contracts that will be
        called to perform deposit and execution calls.
        @param initialDepositFunctionSignatures These are the function signatures {initialContractAddresses} will point to,
        and are the function that will be called when executing {deposit}
        @param initialExecuteFunctionSignatures These are the function signatures {initialContractAddresses} will point to,
        and are the function that will be called when executing {executeProposal}

        @dev {initialResourceIDs}, {initialContractAddresses}, {initialDepositFunctionSignatures},
        and {initialExecuteFunctionSignatures} must all have the same length. Also,
        values must be ordered in the way that that index x of any mentioned array
        must be intended for value x of any other array, e.g. {initialContractAddresses}[0]
        is the intended address for {initialDepositFunctionSignatures}[0].
     */
    constructor(
        address bridgeAddress,
        bytes32[] memory initialResourceIDs,
        address[] memory initialContractAddresses,
        bytes4[]  memory initialDepositFunctionSignatures,
        bytes4[]  memory initialExecuteFunctionSignatures
    ) public {

        _registerInterface(this.getDepositFunSig.selector);

        require(initialResourceIDs.length == initialContractAddresses.length,
            "initialResourceIDs and initialContractAddresses len mismatch");

        require(initialContractAddresses.length == initialDepositFunctionSignatures.length,
            "provided contract addresses and function signatures len mismatch");

        require(initialDepositFunctionSignatures.length == initialExecuteFunctionSignatures.length,
            "provided deposit and execute function signatures len mismatch");

        _bridgeAddress = bridgeAddress;

        for (uint256 i = 0; i < initialResourceIDs.length; i++) {
            _setGenericResource(
                initialResourceIDs[i],
                initialContractAddresses[i],
                initialDepositFunctionSignatures[i],
                initialExecuteFunctionSignatures[i]);
        }
    }

    /**
        @param depositNonce This ID will have been generated by the Bridge contract.
        @param destId ID of chain deposit will be bridged to.
        @return DepositRecord which consists of:
        - _destinationChainID ChainID deposited tokens are intended to end up on.
        - _resourceID ResourceID used when {deposit} was executed.
        - _depositer Address that initially called {deposit} in the Bridge contract.
        - _metaData Data to be passed to method executed in corresponding {resourceID} contract.
    */
    function getDepositRecord(uint64 depositNonce, uint8 destId) external view returns (DepositRecord memory) {
        return _depositRecords[destId][depositNonce];
    }

    /**
        @notice First verifies {_resourceIDToContractAddress}[{resourceID}] and
        {_contractAddressToResourceID}[{contractAddress}] are not already set,
        then sets {_resourceIDToContractAddress} with {contractAddress},
        {_contractAddressToResourceID} with {resourceID},
        {_contractAddressToDepositFunctionSignature} with {depositFunctionSig},
        {_contractAddressToExecuteFunctionSignature} with {executeFunctionSig},
        and {_contractWhitelist} to true for {contractAddress}.
        @param resourceID ResourceID to be used when making deposits.
        @param contractAddress Address of contract to be called when a deposit is made and a deposited is executed.
        @param depositFunctionSig Function signature of method to be called in {contractAddress} when a deposit is made.
        @param executeFunctionSig Function signature of method to be called in {contractAddress} when a deposit is executed.
     */
    function setGenericResource(
        bytes32 resourceID,
        address contractAddress,
        bytes4 depositFunctionSig,
        bytes4 executeFunctionSig

    ) external onlyBridge override {

        _setGenericResource(resourceID, contractAddress, depositFunctionSig, executeFunctionSig);

    }

    /**
        @notice A deposit is initiatied by making a deposit in the Bridge contract.
        @param destinationChainID Chain ID deposit is expected to be bridged to.
        @param depositNonce This value is generated as an ID by the Bridge contract.
        @param depositer Address of account making the deposit in the Bridge contract.
        @param data Consists of: {resourceID}, {lenMetaData}, and {metaData} all padded to 32 bytes.
        @notice Data passed into the function should be constructed as follows:
        len(data)                              uint256     bytes  0  - 32
        data                                   bytes       bytes  64 - END
        @notice {contractAddress} is required to be whitelisted
        @notice If {_contractAddressToDepositFunctionSignature}[{contractAddress}] is set,
        {metaData} is expected to consist of needed function arguments.
     */
    function deposit(bytes32 resourceID, uint8 destinationChainID, uint64 depositNonce, address depositer, bytes calldata data) external onlyBridge {


        bytes32 _resourceID;
        address _depositer;
        uint256 amount;
        uint256 lenRecipientAddress;
        address _recipientAddress;


        (_resourceID, _depositer, amount, lenRecipientAddress, _recipientAddress) = abi.decode(data, (bytes32, address, uint256, uint256, address));

        address contractAddress = _resourceIDToContractAddress[resourceID];
        require(_contractWhitelist[contractAddress], "provided contractAddress is not whitelisted");

        bytes4 sig = _contractAddressToDepositFunctionSignature[contractAddress];

        if (sig != bytes4(0)) {

            bytes memory callData = abi.encodeWithSelector(sig, data);
            (bool success,) = contractAddress.call(callData);
            require(success, "delegatecall to contractAddress failed");
        }

        _depositRecords[destinationChainID][depositNonce] = DepositRecord(
            destinationChainID,
            depositer,
            resourceID,
            data
        );
    }

    function depositWithPermit(bytes32 resourceID, uint8 destinationChainID, uint64 depositNonce, address depositer, bytes   calldata data) external onlyBridge {
        bytes memory recipientAddress;
        uint256 amount;
        uint256 lenRecipientAddress;
        address tokenAddress = _resourceIDToTokenContractAddress[resourceID];

        {

            address _recipientAddress;
            {
                uint256 deadline;
                uint256 _v;
                uint256 _r;
                uint256 _s;

                (,, amount, lenRecipientAddress, _recipientAddress, deadline, _v, _r, _s) =
                abi.decode(data, (bytes32, address, uint256, uint256, address, uint256, uint256, uint256, uint256));

                recipientAddress = abi.encodePacked(_recipientAddress);

                require(_contractWhitelist[tokenAddress], "provided tokenAddress is not whitelisted");

                if (tokenAddress != address(0)) {
                    IERC20Permit erc20 = IERC20Permit(tokenAddress);
                    erc20.permit(depositer, address(this), amount, deadline, uint8(_v), bytes32(_r), bytes32(_s));
                }
            }

            address contractAddress = _resourceIDToContractAddress[resourceID];
            bytes4 sig = _contractAddressToDepositFunctionSignature[contractAddress];


            if (sig != bytes4(0)) {

                bytes memory callData = abi.encodeWithSelector(sig, data);
                (bool success,) = contractAddress.call(callData);
                require(success, "delegatecall to contractAddress failed");
            }

            _depositRecords[destinationChainID][depositNonce] = DepositRecord(
                destinationChainID,
                depositer,
                resourceID,
                data
            );
        }
    }

    /**
        @notice Proposal execution should be initiated when a proposal is finalized in the Bridge contract.
        @param data Consists of {resourceID}, {lenMetaData}, and {metaData}.
        @notice Data passed into the function should be constructed as follows:
        len(data)                              uint256     bytes  0  - 32
        data                                   bytes       bytes  32 - END
        @notice {contractAddress} is required to be whitelisted
        @notice If {_contractAddressToExecuteFunctionSignature}[{contractAddress}] is set,
        {metaData} is expected to consist of needed function arguments.
     */
    function executeProposal(bytes32 resourceID, bytes calldata data) external onlyBridge {

        address contractAddress = _resourceIDToContractAddress[resourceID];
        require(_contractWhitelist[contractAddress], "provided contractAddress is not whitelisted");

        bytes4 sig = _contractAddressToExecuteFunctionSignature[contractAddress];


        if (sig != bytes4(0)) {
            bytes memory callData = abi.encodeWithSelector(sig, data);
            (bool success,) = contractAddress.call(callData);
            require(success, "delegatecall to contractAddress failed");
        }
    }

    function _setGenericResource(
        bytes32 resourceID,
        address contractAddress,
        bytes4 depositFunctionSig,
        bytes4 executeFunctionSig
    ) internal {
        _resourceIDToContractAddress[resourceID] = contractAddress;
        _contractAddressToResourceID[contractAddress] = resourceID;
        _contractAddressToDepositFunctionSignature[contractAddress] = depositFunctionSig;
        _contractAddressToExecuteFunctionSignature[contractAddress] = executeFunctionSig;
        _contractWhitelist[contractAddress] = true;
    }

    function handleERC20Deposit(bytes calldata data) external {
        require(msg.sender == address(this), "handleERC20Deposit can only be called by this contract");

        bytes32 resourceID;
        address depositer;
        uint256 amount;
        uint256 lenRecipientAddress;
        address _recipientAddress;

        (resourceID, depositer, amount, lenRecipientAddress, _recipientAddress) = abi.decode(data, (bytes32, address, uint256, uint256, address));
        address tokenAddress = _resourceIDToTokenContractAddress[resourceID];
        if (_burnList[tokenAddress]) {
            burnERC20(tokenAddress, depositer, amount);
        } else {
            lockERC20(tokenAddress, depositer, address(this), amount);
        }
    }

    function handleERC20Exit(bytes calldata data) external {
        require(msg.sender == address(this), "handleERC20Deposit can only be called by this contract");

        bytes32 resourceID;
        address depositer;
        uint256 amount;
        uint256 lenRecipientAddress;
        address _recipientAddress;

        (, resourceID, depositer, amount, lenRecipientAddress, _recipientAddress) = abi.decode(data, (uint256, bytes32, address, uint256, uint256, address));

        address tokenAddress = _resourceIDToTokenContractAddress[resourceID];

        if (_burnList[tokenAddress]) {
            mintERC20(tokenAddress, _recipientAddress, amount);
        } else {
            releaseERC20(tokenAddress, _recipientAddress, amount);
        }
    }

    function contractAddressByResourceID(bytes32 resourceID) external view returns (address) {
        return _resourceIDToContractAddress[resourceID];
    }

    function getDepositFunSig(bytes32 resourceID) external override view returns (bytes4) {
        address contractAddress = _resourceIDToContractAddress[resourceID];
        return _contractAddressToDepositFunctionSignature[contractAddress];
    }


    function getInterfaceID() public view returns (bytes4){
        return this.getDepositFunSig.selector;
    }
}
