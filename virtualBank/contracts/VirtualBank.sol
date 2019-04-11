pragma solidity ^0.5.1;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/utils/Address.sol";
import "openzeppelin-solidity/contracts/cryptography/ECDSA.sol";

/**
 * @title Virtual bank smart contract. Support RSMC and HTLC commitments.
 * @dev Simulate the lightning network clearing protocol with Solidity programming language.
 */
contract VirtualBank {
    using SafeMath for uint256;
    using ECDSA for bytes32;

    string[2] NAMES = [string("Alice"), "Bob"];

    // balance sheets
    uint160[2] _addrs;   // Alice's and Bob's addresses
    uint256[2] _amounts;      // _amounts of each account
    bool[2]    _depositeds;   // whether each account deposit enough fund

    struct Commitment {
        uint32     sequence;
        uint8      attacker;      // defender = 1 - attacker
        address    revocationLock;
        uint       freezeTime;
        uint       requestTime;
        uint256[2] amounts;        // amount[attacker] is fidelity bond
    }

    // enum for virtual bank state
    enum State { Funding, Running, Auditing, Closed }

    // state of virtual bank
    State  _state;

    // commitment data
    Commitment  _commitment;

    // Event for Virtual Bank State Transition
    event VirtualBankFunding(uint160 alice, uint256 amountAlice, uint160 bob, uint256 amountBob);

    event VirtualBankRunning(uint160 alice, uint256 amountAlice, uint160 bob, uint256 amountBob);

    event VirtualBankAuditing();

    event VirtualBankClosed();

    // Event for Fund deposit, Freeze and Withdraw
    event Deposit(string name, address addr, uint256 amountAlice);

    event FreezeFidelityBond(uint32 sequence, string attackerName, uint256 amount, address revocationLock, uint expireTime);

    event Withdraw(uint32 sequence, string recipient, address addr, uint256 amount);

    // Event for Commitment Message
    event ProcessCommitment(uint32 sequence, string attacker);

    event RSMCPart(uint256 amountAlice, uint256 amountBob, 
                   address revocationLock, uint expireTime);

    event HTLCPart( uint amountAliceHTLC, uint amountBobHTLC,
                    bytes32 hashLock,  bytes preimage, 
                    uint timeLock);

    event RevocationLockOpened(uint32 sequence, uint requestTime, address revocationLock);

    event TimeLockExpire(uint32 sequence, uint requestTime, uint timeLock);

    event HashLockOpened(uint32 sequence, bytes32 hashLock,  bytes preimage, uint time);

    modifier isFunding() {
        require(_state == State.Funding,"Should be in Funding state.");
        _;
    }

    modifier isRunning() {
        require(_state == State.Running,"Should be in Running state.");
        _;
    }

    modifier isAuditing() {
        require(_state == State.Auditing,"Should be in Auditing state.");
        _;
    }

    modifier validAddress(address addr) {
        require(addr != address(0),"address should not be null.");
        _;
    }

    modifier onlyAttacker(address addr) {
        require(addr == address(_addrs[_commitment.attacker]), "Only attacker can make this call.");
        _;
    }

    modifier onlyDefender(address addr) {
        require(addr == address(_addrs[1 - _commitment.attacker]), "Only defender can make this call.");
        _;
    }

    /**
     * @notice The contructor of virtual bank smart contract
     * @param addrs  Addresses of Alice and Bob
     * @param amounts Balance amount of Alice and Bob
     */
    constructor(uint160[2] memory addrs,  uint256[2] memory amounts) 
    public validAddress(address(addrs[0]))  validAddress(address(addrs[1])) {
        _addrs = [addrs[0], addrs[1]];
        _amounts = [amounts[0], amounts[1]];
        _depositeds = [false, false];

        _commitment = Commitment(0, 0, address(0), 0, 0, [uint256(0), 0]);
        _state = State.Funding;
        emit VirtualBankFunding(_addrs[0], _amounts[0], _addrs[1], _amounts[1]);
    }

    /**
     * @notice Alice or Bob deposit fund to virtual bank.
     */
    function deposit()  external payable isFunding() {

        if(msg.sender == address(_addrs[0]) && msg.value == _amounts[0] && !_depositeds[0]) {
            _depositeds[0] = true;
            emit Deposit("Alice", msg.sender, msg.value);

        } else if (msg.sender == address(_addrs[1]) && msg.value == _amounts[1] && !_depositeds[1]) {
            _depositeds[1] = true;
            emit Deposit("Bob", msg.sender, msg.value);

        } else {
            revert();
        }

        // If both Alice and Bob have _depositeds fund, virtual bank begin running.
        if (_depositeds[0] && _depositeds[1]) {
            _state = State.Running;
            emit VirtualBankRunning(_addrs[0], _amounts[0], _addrs[1], _amounts[1]);
        }
    }

    /**
     * @notice Virtual bank cash a RSMC commitment which is submitted by Alice or Bob.
     * @param sequence          The sequence number of the commitment.
     * @param amounts           The amounts of new balance sheet
     * @param revocationLock    The revocation lock for attacker's findelity bond.
     * @param freezeTime        The freeze time for attacker's findelity bond.
     * @param defenderSignature The defender's signature.
     */
    function cashRsmc(uint32 sequence, uint256[2] calldata amounts, address revocationLock, 
                      uint freezeTime, bytes calldata defenderSignature) 
                external isRunning() validAddress(revocationLock) {

        require((amounts[0] + amounts[1]) == (_amounts[0] + _amounts[1]), 
                "Total amount doesn't match.");

        // identify attacker's index
        uint8 attacker = findAttacker();
        uint8 defender = 1 - attacker;

        // check defender's signature over sequence, revocation lock, new balance sheet, freeze time
        bytes32 msgHash = keccak256(abi.encodePacked(address(this), sequence, 
                                    amounts[0], amounts[1], revocationLock, freezeTime));
        require(checkSignature(msgHash, defenderSignature, address(_addrs[defender])));
        
        uint requestTime = now;
        emit ProcessCommitment(sequence, NAMES[attacker]);

        emit RSMCPart(amounts[0], amounts[1], 
                      revocationLock, requestTime + freezeTime);

        _commitment.sequence = sequence;
        _commitment.attacker = attacker;
        _commitment.revocationLock = revocationLock;
        _commitment.requestTime = requestTime;
        _commitment.freezeTime = freezeTime;
        _commitment.amounts[0] = amounts[0];
        _commitment.amounts[1] = amounts[1];
        _doCommitment();
    }

    /**
     * @notice Virtual bank cash a HTLC commitment which is submitted by Alice or Bob.
     * @param sequence          The sequence number of the commitment.
     * @param rsmcAmounts       Virtual bank settle fund according to this balance sheet if 
     *                          HTLC time lock expire.
     * @param revocationLock    The revocation lock for attacker's findelity bond.
     * @param freezeTime        The freeze time for attacker's findelity bond.
     * @param hashLock          The hash lock in HTLC commitment.
     * @param preimage          The pre-image for the hash lock.
     * @param timeLock          The time lock in HTLC commitment.
     * @param htlcAmounts       Virtual bank settle fund according to this balance sheet if 
     *                          both time lock and hash lock are satisfied.
     * @param defenderSignature The defender's signature.
     */
    function cashHtlc(uint32  sequence,    uint256[2] calldata rsmcAmounts, 
                  address revocationLock,  uint       freezeTime, 
                  bytes32 hashLock,        bytes      calldata preimage,
                  uint    timeLock,        uint[2]    calldata htlcAmounts,
                  bytes   calldata defenderSignature) 
            external isRunning() validAddress(revocationLock){

        // check rsmcAmounts
        require((rsmcAmounts[0] + rsmcAmounts[1]) == (_amounts[0] + _amounts[1]), 
                "rsmcAmounts total amount doesn't match.");

        // check htlcAmounts
        require((htlcAmounts[0] + htlcAmounts[1]) == (_amounts[0] + _amounts[1]), 
                "htlcAmounts total amount doesn't match.");

        // identify attacker's index
        uint8 attacker = findAttacker();
        // uint8 defender = 1- attacker;

        // check defender signature over parameters
        bytes32 msgHash = keccak256(abi.encodePacked(sequence, rsmcAmounts[0], 
                                    rsmcAmounts[1], revocationLock, freezeTime, hashLock, 
                                    timeLock, htlcAmounts[0], htlcAmounts[1]));
        require(checkSignature(msgHash, defenderSignature, address(_addrs[1- attacker])));
 
        uint requestTime = now;

        emit ProcessCommitment(sequence, NAMES[attacker]);

        emit RSMCPart(rsmcAmounts[0], rsmcAmounts[1], 
                      revocationLock, requestTime + freezeTime);

        emit HTLCPart(htlcAmounts[0], htlcAmounts[1], hashLock, preimage, timeLock);
        // check time lock
        if (requestTime >= timeLock){
            emit TimeLockExpire(sequence, requestTime, timeLock);

            // if time lock expire, handle this commitment as RSMC
            _commitment.sequence = sequence;
            _commitment.attacker = attacker;
            _commitment.revocationLock = revocationLock;
            _commitment.requestTime = requestTime;
            _commitment.freezeTime = freezeTime;
            _commitment.amounts[0] = rsmcAmounts[0];
            _commitment.amounts[1] = rsmcAmounts[1];
            _doCommitment();

        } else {
            // check msgHash lock
            require (keccak256(preimage) == hashLock);
            // emit HashLockOpened(sequence, hashLock, preimage, requestTime);

            _commitment.sequence = sequence;
            _commitment.attacker = attacker;
            _commitment.revocationLock = revocationLock;
            _commitment.requestTime = requestTime;
            _commitment.freezeTime = freezeTime;
            _commitment.amounts[0] = htlcAmounts[0];
            _commitment.amounts[1] = htlcAmounts[1];
            // if both time lock and hash lock are satisfied, handle this commitment as HTLC
            _doCommitment();
        }
    }

    /**
     * @notice After freezing time, attacker withdraws his fidelity bond.
     */
    function withdrawByAttacker() external isAuditing() onlyAttacker(msg.sender) {

        require(now >= _commitment.requestTime + _commitment.freezeTime);

        _state = State.Closed;
        emit VirtualBankClosed();

        // send fidelity bond back to attacker
        uint attacker = _commitment.attacker;
        uint256 amount = _commitment.amounts[attacker];
        msg.sender.transfer(amount);
        emit Withdraw(_commitment.sequence, NAMES[attacker], msg.sender, amount);
    }

    /**
     * @notice Defender solve the revocation lock, withdraws attacker's fidelity bond as penalty.
     * @param revocationSignature  Defender's signature to open the revocation lock.
     */
    function withdrawByDefender( bytes calldata revocationSignature) 
            external isAuditing() onlyDefender(msg.sender) {
        uint attacker = _commitment.attacker;
        uint defender = 1 - attacker;

        // check signature for revocation lock
        bytes32 msgHash = keccak256(abi.encodePacked(address(this), _commitment.sequence));
        require(checkSignature(msgHash, revocationSignature, _commitment.revocationLock));
        emit RevocationLockOpened( _commitment.sequence, now, _commitment.revocationLock);

        // Close virtual bank;
        _state = State.Closed;
        emit VirtualBankClosed();

        // send fidelity bond to defender
        uint256 amount = _commitment.amounts[attacker];
        msg.sender.transfer(amount);
        emit Withdraw(_commitment.sequence, NAMES[defender], msg.sender, amount);
    }

    /**
     * @notice Virtual bank settle defender's fund immediately, and freeze the attacker's 
     *         fund as fidelity bond.
     */
    function _doCommitment() internal {
        _state = State.Auditing;
        emit VirtualBankAuditing();

        // send fund to defender now
        uint8 defender = 1 - _commitment.attacker;
        address payable defenderAddr = address(_addrs[defender]);
        defenderAddr.transfer(_commitment.amounts[defender]);

        emit Withdraw(_commitment.sequence, 
                      NAMES[defender], 
                      defenderAddr, 
                      _commitment.amounts[defender]);

        emit FreezeFidelityBond(_commitment.sequence, 
                                NAMES[_commitment.attacker], 
                                _commitment.amounts[_commitment.attacker], 
                                _commitment.revocationLock, 
                                _commitment.requestTime + _commitment.freezeTime);
    }

    /**
     * @notice find the attacker's index according the sender's address
     * @return 0 for Alice, and 1 for Bob
     */
    function findAttacker() internal view returns (uint8 attacker) {
        if (msg.sender == address(_addrs[0])) {
            attacker = 0;
        } else if (msg.sender == address(_addrs[1])) {
            attacker = 1;
        } else {
            revert();
        }
    }

    /**
     * @notice Check signture.
     * @param msgHash          Message hashs
     * @param signature     Signature bytes      
     * @param expectedAddr  expected address
     * @return If the signature match the expected address.
     */
    function checkSignature( bytes32 msgHash, bytes memory signature, address expectedAddr) internal pure returns (bool){

        bytes32 messageHash = msgHash.toEthSignedMessageHash();

        // Verify that the message's signer is the owner of the order
        address signer = messageHash.recover(signature);
        return (signer == expectedAddr);
    }
}