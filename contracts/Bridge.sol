pragma solidity 0.6.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./utils/Pausable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IDepositExecute.sol";
import "./interfaces/IBridge.sol";
import "./interfaces/IERCHandler.sol";
import "./interfaces/IGenericHandler.sol";
import "./utils/ChainId.sol";
import "@openzeppelin/contracts/introspection/ERC165Checker.sol";

/**
    @title Facilitates deposits, creation and voting of deposit proposals, and deposit executions.
    @author ChainSafe Systems.
 */
contract Bridge is Pausable, AccessControl {
    using SafeMath for uint256;
    using SafeMath for uint64;

    uint8   public _chainID;
    uint256 public _relayerThreshold;
    uint256 public _totalRelayers;
    uint256 public _totalProposals;
    uint256 public _fee;
    uint256 public _expiry;

    enum Vote {No, Yes}

    enum ProposalStatus {Inactive, Active, Passed, Executed, Cancelled}

    struct Proposal {
        bytes32 _resourceID;
        bytes32 _dataHash;
        address[] _yesVotes;
        address[] _noVotes;
        ProposalStatus _status;
        uint256 _proposedBlock;
    }

    // destinationChainID => number of deposits
    mapping(uint8 => uint64) public _depositCounts;
    // resourceID => handler address
    mapping(bytes32 => address) public _resourceIDToHandlerAddress;
    // depositNonce => destinationChainID => bytes
    mapping(uint64 => mapping(uint8 => bytes)) public _depositRecords;
    // destinationChainID + depositNonce => dataHash => Proposal
    mapping(uint72 => mapping(bytes32 => Proposal)) public _proposals;
    // destinationChainID + depositNonce => dataHash => relayerAddress => bool
    mapping(uint72 => mapping(bytes32 => mapping(address => bool))) public _hasVotedOnProposal;


    event RelayerThresholdChanged(uint indexed newThreshold);
    event RelayerAdded(address indexed relayer);
    event RelayerRemoved(address indexed relayer);
    event Deposit(
        uint8   indexed destinationChainID,
        bytes32 indexed resourceID,
        uint64  indexed depositNonce
    );
    event ProposalEvent(
        uint8           indexed originChainID,
        uint64          indexed depositNonce,
        ProposalStatus  indexed status,
        bytes32 resourceID,
        bytes32 dataHash
    );

    event ProposalVote(
        uint8   indexed originChainID,
        uint64  indexed depositNonce,
        ProposalStatus indexed status,
        bytes32 resourceID
    );

    event AddEthFund(
        uint256 amount
    );

    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");
    bytes32 public constant TRUSTED_HANDLER_ROLE = keccak256("TRUSTED_HANDLER_ROLE");

    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    modifier onlyAdminOrRelayer() {
        _onlyAdminOrRelayer();
        _;
    }

    modifier onlyRelayers() {
        _onlyRelayers();
        _;
    }
    modifier onlyTrustedHandlers() {
        _onlyTrustedHandlers();
        _;
    }


    function _onlyAdminOrRelayer() private {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(RELAYER_ROLE, msg.sender),
            "sender is not relayer or admin");
    }

    function _onlyAdmin() private {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "sender doesn't have admin role");
    }

    function _onlyRelayers() private {
        require(hasRole(RELAYER_ROLE, msg.sender), "sender doesn't have relayer role");
    }

    function _onlyTrustedHandlers() private {
        require(hasRole(TRUSTED_HANDLER_ROLE, msg.sender), "sender doesn't have release trusted handler role");
    }

    /**
        @notice Initializes Bridge, creates and grants {msg.sender} the admin role,
        creates and grants {initialRelayers} the relayer role.
        @param chainID ID of chain the Bridge contract exists on.
        @param initialRelayers Addresses that should be initially granted the relayer role.
        @param initialRelayerThreshold Number of votes needed for a deposit proposal to be considered passed.
     */
    constructor (uint8 chainID, address[] memory initialRelayers, uint initialRelayerThreshold, uint256 fee, uint256 expiry) public {
        _chainID = chainID;
        _relayerThreshold = initialRelayerThreshold;
        _fee = fee;
        _expiry = expiry;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(RELAYER_ROLE, DEFAULT_ADMIN_ROLE);

        for (uint i; i < initialRelayers.length; i++) {
            grantRole(RELAYER_ROLE, initialRelayers[i]);
        }
        _setRoleAdmin(TRUSTED_HANDLER_ROLE, DEFAULT_ADMIN_ROLE);
    }

    function getChainId() external view returns (uint8) {
        return _chainID;
    }


    /**
    * @dev Grants `role` to `account`. override grantRole to increase _totalRelayers
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) public override {

        if (role == RELAYER_ROLE) {
            if (!hasRole(RELAYER_ROLE, account)){
                _totalRelayers = _totalRelayers.add(1);
            }
        }
        super.grantRole(role, account);
    }

    /**
        * @dev Revokes `role` from `account`. override revokeRole to decrease _totalRelayers
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) public override {
        if (role == RELAYER_ROLE) {
            if (hasRole(RELAYER_ROLE, account)){
                _totalRelayers = _totalRelayers.sub(1);
            }
        }
        super.revokeRole(role, account);
    }

    /**
    * @dev Revokes `role` from the calling account. override renounceRole to decrease _totalRelayers
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been granted `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     */
    function renounceRole(bytes32 role, address account) public override {
        require(role != DEFAULT_ADMIN_ROLE, "Bridge: cannot renounce admin role");
        if (role == RELAYER_ROLE) {
            if (hasRole(RELAYER_ROLE, account)){
                _totalRelayers = _totalRelayers.sub(1);
            }
        }
        super.renounceRole(role, account);
    }

    /**
        @notice Returns true if {relayer} has the relayer role.
        @param relayer Address to check.
     */
    function isRelayer(address relayer) external view returns (bool) {
        return hasRole(RELAYER_ROLE, relayer);
    }


    /**
        @notice Pauses deposits, proposal creation and voting, and deposit executions.
        @notice Only callable by an address that currently has the admin role.
     */
    function adminPauseTransfers() external onlyAdmin {
        _pause();
    }

    /**
        @notice Unpauses deposits, proposal creation and voting, and deposit executions.
        @notice Only callable by an address that currently has the admin role.
     */
    function adminUnpauseTransfers() external onlyAdmin {
        _unpause();
    }

    /**
        @notice Modifies the number of votes required for a proposal to be considered passed.
        @notice Only callable by an address that currently has the admin role.
        @param newThreshold Value {_relayerThreshold} will be changed to.
        @notice Emits {RelayerThresholdChanged} event.
     */
    function adminChangeRelayerThreshold(uint newThreshold) external onlyAdmin {
        require(newThreshold > 0, "new threshold must be greater than 0");
        _relayerThreshold = newThreshold;
        emit RelayerThresholdChanged(newThreshold);
    }

    /**
        @notice Grants {relayerAddress} the relayer role and increases {_totalRelayer} count.
        @notice Only callable by an address that currently has the admin role.
        @param relayerAddress Address of relayer to be added.
        @notice Emits {RelayerAdded} event.
     */
    function adminAddRelayer(address relayerAddress) external onlyAdmin {
        require(!hasRole(RELAYER_ROLE, relayerAddress), "addr already has relayer role!");
        grantRole(RELAYER_ROLE, relayerAddress);
        emit RelayerAdded(relayerAddress);
    }

    /**
        @notice Removes relayer role for {relayerAddress} and decreases {_totalRelayer} count.
        @notice Only callable by an address that currently has the admin role.
        @param relayerAddress Address of relayer to be removed.
        @notice Emits {RelayerRemoved} event.
     */
    function adminRemoveRelayer(address relayerAddress) external onlyAdmin {
        require(hasRole(RELAYER_ROLE, relayerAddress), "addr doesn't have relayer role!");
        revokeRole(RELAYER_ROLE, relayerAddress);
        emit RelayerRemoved(relayerAddress);
    }

    /**
        @notice Sets a new resource for handler contracts that use the IERCHandler interface,
        and maps the {handlerAddress} to {resourceID} in {_resourceIDToHandlerAddress}.
        @notice Only callable by an address that currently has the admin role.
        @param handlerAddress Address of handler resource will be set for.
        @param resourceID ResourceID to be used when making deposits.
        @param tokenAddress Address of contract to be called when a deposit is made and a deposited is executed.
     */
    function adminSetResource(address handlerAddress, bytes32 resourceID, address tokenAddress) external onlyAdmin {
        _resourceIDToHandlerAddress[resourceID] = handlerAddress;
        IERCHandler handler = IERCHandler(handlerAddress);
        handler.setResource(resourceID, tokenAddress);
    }

    /**
        @notice handler addresses that are trusted to execute release Ether fund from this bridge contract to depositors
    */
    function adminSetTrustedHandlers(address _handlerAddress) external onlyAdmin {
        require(!hasRole(TRUSTED_HANDLER_ROLE, _handlerAddress), "handler address already has TRUSTED_HANDLER_ROLE role");
        grantRole(TRUSTED_HANDLER_ROLE, _handlerAddress);
    }

    /**
        @notice Sets a new resource for handler contracts that use the IGenericHandler interface,
        and maps the {handlerAddress} to {resourceID} in {_resourceIDToHandlerAddress}.
        @notice Only callable by an address that currently has the admin role.
        @param handlerAddress Address of handler resource will be set for.
        @param resourceID ResourceID to be used when making deposits.
        @param contractAddress Address of contract to be called when a deposit is made and a deposited is executed.
     */
    function adminSetGenericResource(
        address handlerAddress,
        bytes32 resourceID,
        address contractAddress,
        bytes4 depositFunctionSig,
        bytes4 executeFunctionSig
    ) external onlyAdmin {
        _resourceIDToHandlerAddress[resourceID] = handlerAddress;
        IGenericHandler handler = IGenericHandler(handlerAddress);
        handler.setGenericResource(resourceID, contractAddress, depositFunctionSig, executeFunctionSig);
    }

    /**
        @notice Sets a resource as burnable for handler contracts that use the IERCHandler interface.
        @notice Only callable by an address that currently has the admin role.
        @param handlerAddress Address of handler resource will be set for.
        @param tokenAddress Address of contract to be called when a deposit is made and a deposited is executed.
     */
    function adminSetBurnable(address handlerAddress, address tokenAddress) external onlyAdmin {
        IERCHandler handler = IERCHandler(handlerAddress);
        handler.setBurnable(tokenAddress);
    }

    /**
        @notice Returns a proposal.
        @param originChainID Chain ID deposit originated from.
        @param depositNonce ID of proposal generated by proposal's origin Bridge contract.
        @param dataHash Hash of data to be provided when deposit proposal is executed.
        @return Proposal which consists of:
        - _dataHash Hash of data to be provided when deposit proposal is executed.
        - _yesVotes Number of votes in favor of proposal.
        - _noVotes Number of votes against proposal.
        - _status Current status of proposal.
     */
    function getProposal(uint8 originChainID, uint64 depositNonce, bytes32 dataHash) external view returns (Proposal memory) {
        uint72 nonceAndID = (uint72(depositNonce) << 8) | uint72(originChainID);
        return _proposals[nonceAndID][dataHash];
    }

    /**
        @notice Changes deposit fee.
        @notice Only callable by admin.
        @param newFee Value {_fee} will be updated to.
     */
    function adminChangeFee(uint newFee) external onlyAdmin {
        require(_fee != newFee, "Current fee is equal to new fee");
        _fee = newFee;
    }


    /**
        @notice Initiates a transfer using a specified handler contract.
        @notice Only callable when Bridge is not paused.
        @param destinationChainID ID of chain deposit will be bridged to.
        @param resourceID ResourceID used to find address of handler to be used for deposit.
        @param data Additional data to be passed to specified handler.
        @notice Emits {Deposit} event.
     */

    function deposit(uint8 destinationChainID, bytes32 resourceID, bytes calldata data) external payable whenNotPaused {
        //require(msg.value == _fee, "Incorrect fee supplied");

        address handler = _resourceIDToHandlerAddress[resourceID];
        require(handler != address(0), "resourceID not mapped to handler");
        _depositCounts[destinationChainID] = uint64(_depositCounts[destinationChainID].add(1));
        uint64 depositNonce = _depositCounts[destinationChainID];
        _depositRecords[depositNonce][destinationChainID] = data;

        IDepositExecute depositHandler = IDepositExecute(handler);

        //check deposit sig of the handler,
        // if deposit funcSig is null, then msg.value should be used for proceed.
        //if (supportsInterface (address(depositHandler),  )

        if (ERC165Checker.supportsInterface(address(handler), 0x6c0fbf3e)) {//0x6c0fbf3e => getDepositFunSig(bytes32)
            IGenericHandler genericHandler = IGenericHandler(handler);
            bytes4 sig = genericHandler.getDepositFunSig(resourceID);

            if (sig != bytes4(0)) {

                depositHandler.deposit(resourceID, destinationChainID, depositNonce, msg.sender, data);
                emit Deposit(destinationChainID, resourceID, depositNonce);
            } else {

                //is generic handler and trying to deposit ETH to the handler
                //check msg.value is amount
                require(msg.value > 0, "msg.value should be greater than 0");
                bytes32 _resourceID;
                address depositer;
                uint256 amount;
                //                    uint256 lenRecipientAddress;
                //                    address _recipientAddress;

                (_resourceID, depositer, amount,,) = abi.decode(data, (bytes32, address, uint256, uint256, address));
                require(amount == msg.value, "amount should be less than msg.value");
                //proceed deposit
                depositHandler.deposit(resourceID, destinationChainID, depositNonce, msg.sender, data);
                emit Deposit(destinationChainID, resourceID, depositNonce);
            }
        } else {
            //proceed deposit

            depositHandler.deposit(resourceID, destinationChainID, depositNonce, msg.sender, data);
            emit Deposit(destinationChainID, resourceID, depositNonce);
        }


    }


    function depositWithPermit(uint8 destinationChainID, bytes32 resourceID, bytes calldata data) external payable whenNotPaused {

        address handler = _resourceIDToHandlerAddress[resourceID];
        require(handler != address(0), "resourceID not mapped to handler");
        _depositCounts[destinationChainID] = uint64(_depositCounts[destinationChainID].add(1));
        uint64 depositNonce = _depositCounts[destinationChainID];
        _depositRecords[depositNonce][destinationChainID] = data;
        IDepositExecute depositHandler = IDepositExecute(handler);


        if (ERC165Checker.supportsInterface(address(handler), 0x6c0fbf3e)) {//0x6c0fbf3e => getDepositFunSig(bytes32)
            IGenericHandler genericHandler = IGenericHandler(handler);
            bytes4 sig = genericHandler.getDepositFunSig(resourceID);
            if (sig != bytes4(0)) {
                depositHandler.depositWithPermit(resourceID, destinationChainID, depositNonce, msg.sender, data);
                emit Deposit(destinationChainID, resourceID, depositNonce);
            } else {

                //is generic handler and trying to deposit ETH to the handler
                //check msg.value is amount
                require(msg.value > 0, "msg.value should be greater than 0");
                bytes32 _resourceID;
                address depositer;
                uint256 amount;

                (_resourceID, depositer, amount,,) = abi.decode(data, (bytes32, address, uint256, uint256, address));
                require(amount <= msg.value, "amount should be less than msg.value");

                //proceed deposit
                depositHandler.depositWithPermit(resourceID, destinationChainID, depositNonce, msg.sender, data);
                emit Deposit(destinationChainID, resourceID, depositNonce);
            }
        } else {
            //proceed deposit
            depositHandler.depositWithPermit(resourceID, destinationChainID, depositNonce, msg.sender, data);
            emit Deposit(destinationChainID, resourceID, depositNonce);
        }

    }


    function tokenAddressByResourceId(bytes32 resourceID) external view returns (address) {
        address handlerAddress = _resourceIDToHandlerAddress[resourceID];
        IERCHandler handler = IERCHandler(handlerAddress);
        return handler.tokenAddressByResourceID(resourceID);
    }

    function handlerAddressByResourceId(bytes32 resourceID) external view returns (address) {
        address handlerAddress = _resourceIDToHandlerAddress[resourceID];
        return handlerAddress;
    }

    /**
        @notice When called, {msg.sender} will be marked as voting in favor of proposal.
        @notice Only callable by relayers when Bridge is not paused.
        @param chainID ID of chain deposit originated from.
        @param depositNonce ID of deposited generated by origin Bridge contract.
        @param dataHash Hash of data provided when deposit was made.
        @notice Proposal must not have already been passed or executed.
        @notice {msg.sender} must not have already voted on proposal.
        @notice Emits {ProposalEvent} event with status indicating the proposal status.
        @notice Emits {ProposalVote} event.
     */
    function voteProposal(uint8 chainID, uint64 depositNonce, bytes32 resourceID, bytes32 dataHash) external onlyRelayers whenNotPaused {

        uint72 nonceAndID = (uint72(depositNonce) << 8) | uint72(chainID);
        Proposal storage proposal = _proposals[nonceAndID][dataHash];

        require(_resourceIDToHandlerAddress[resourceID] != address(0), "no handler for resourceID");
        require(uint(proposal._status) <= 1, "proposal already passed/executed/cancelled");
        require(!_hasVotedOnProposal[nonceAndID][dataHash][msg.sender], "relayer already voted");

        if (uint(proposal._status) == 0) {
            _totalProposals = _totalProposals.add(1);
            _proposals[nonceAndID][dataHash] = Proposal({
            _resourceID : resourceID,
            _dataHash : dataHash,
            _yesVotes : new address[](1),
            _noVotes : new address[](0),
            _status : ProposalStatus.Active,
            _proposedBlock : block.number
            });

            proposal._yesVotes[0] = msg.sender;
            emit ProposalEvent(chainID, depositNonce, ProposalStatus.Active, resourceID, dataHash);
        } else {
            if (block.number.sub(proposal._proposedBlock) > _expiry) {
                // if the number of blocks that has passed since this proposal was
                // submitted exceeds the expiry threshold set, cancel the proposal
                proposal._status = ProposalStatus.Cancelled;
                emit ProposalEvent(chainID, depositNonce, ProposalStatus.Cancelled, resourceID, dataHash);
            } else {
                require(dataHash == proposal._dataHash, "datahash mismatch");
                proposal._yesVotes.push(msg.sender);


            }

        }
        if (proposal._status != ProposalStatus.Cancelled) {
            _hasVotedOnProposal[nonceAndID][dataHash][msg.sender] = true;
            emit ProposalVote(chainID, depositNonce, proposal._status, resourceID);

            // If _depositThreshold is set to 1, then auto finalize
            // or if _relayerThreshold has been exceeded
            if (_relayerThreshold <= 1 || proposal._yesVotes.length >= _relayerThreshold) {
                proposal._status = ProposalStatus.Passed;

                emit ProposalEvent(chainID, depositNonce, ProposalStatus.Passed, resourceID, dataHash);
            }
        }

    }

    /**
@notice Executes a cancel proposal
        @notice Only callable by relayers when Bridge is not paused.
        @param chainID ID of chain deposit originated from.
        @param depositNonce ID of deposited generated by origin Bridge contract.
        @param dataHash Hash of data originally provided when deposit was made.
     */
    function cancelProposal(uint8 chainID, uint64 depositNonce, bytes32 dataHash) public onlyAdminOrRelayer {
        uint72 nonceAndID = (uint72(depositNonce) << 8) | uint72(chainID);
        Proposal storage proposal = _proposals[nonceAndID][dataHash];

        require(proposal._status != ProposalStatus.Cancelled, "Proposal already cancelled");
        require(block.number.sub(proposal._proposedBlock) > _expiry, "Proposal not at expiry threshold");

        proposal._status = ProposalStatus.Cancelled;
        emit ProposalEvent(chainID, depositNonce, ProposalStatus.Cancelled, proposal._resourceID, proposal._dataHash);

    }

    /**
@notice Executes a deposit proposal that is considered passed using a specified handler contract.
        @notice Only callable by relayers when Bridge is not paused.
        @param chainID ID of chain deposit originated from.
        @param resourceID ResourceID to be used when making deposits.
        @param depositNonce ID of deposited generated by origin Bridge contract.
        @param data Data originally provided when deposit was made.
        @notice Proposal must have Passed status.
        @notice Hash of {data} must equal proposal's {dataHash}.
        @notice Emits {ProposalEvent} event with status {Executed}.
     */
    function executeProposal(uint8 chainID, uint64 depositNonce, bytes calldata data, bytes32 resourceID) external onlyRelayers whenNotPaused {
        address handler = _resourceIDToHandlerAddress[resourceID];
        uint72 nonceAndID = (uint72(depositNonce) << 8) | uint72(chainID);
        bytes32 dataHash = keccak256(abi.encodePacked(handler, data));
        Proposal storage proposal = _proposals[nonceAndID][dataHash];

        require(proposal._status != ProposalStatus.Inactive, "proposal is not active");
        require(proposal._status == ProposalStatus.Passed, "proposal already transferred");
        require(dataHash == proposal._dataHash, "data doesn't match datahash");

        proposal._status = ProposalStatus.Executed;

        IDepositExecute depositHandler = IDepositExecute(_resourceIDToHandlerAddress[proposal._resourceID]);
        depositHandler.executeProposal(proposal._resourceID, data);

        emit ProposalEvent(chainID, depositNonce, proposal._status, proposal._resourceID, proposal._dataHash);
    }

//    /**
//        @notice Transfers eth in the contract to the specified addresses. The parameters addrs and amounts are mapped 1-1.
//        This means that the address at index 0 for addrs will receive the amount (in WEI) from amounts at index 0.
//        @param addrs Array of addresses to transfer {amounts} to.
//        @param amounts Array of amonuts to transfer to {addrs}.
//     */
////    function transferFunds(address payable[] calldata addrs, uint[] calldata amounts) external onlyAdmin {
////        for (uint i = 0; i < addrs.length; i++) {
////            addrs[i].transfer(amounts[i]);
////        }
////    }

    function releaseEth(bytes calldata metaData) external onlyTrustedHandlers {
        bytes32 resourceID;
        address depositer;
        uint256 amount;
        uint256 lenRecipientAddress;
        address payable _recipientAddress;
        (, resourceID, depositer, amount, lenRecipientAddress, _recipientAddress) = abi.decode(metaData, (uint256, bytes32, address, uint256, uint256, address));
        require(_resourceIDToHandlerAddress[resourceID] != address(0), "invalid resourceID");
        require(depositer != address(0), "invalid depositer");
        require(lenRecipientAddress >0, "invalid recipient address length");
        require(_recipientAddress != address(0), "invalid recipient address");
        require(amount > 0, "amount must be greater than 0");
        require(address(this).balance >= amount, "insufficient ETH fund");

        (bool sent, bytes memory data) = _recipientAddress.call{value: amount}("");
        require(sent, "Failed to send Ether");

    }

    function addEthFund() external payable onlyAdmin {
        emit AddEthFund(msg.value);
    }

    function getEvmNetworkChainId() public view returns (uint256) {
        return ChainId.get();
    }
}
