pragma solidity ^0.5.1;

import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "zeppelin-solidity/contracts/AddressUtils.sol";
import "zeppelin-solidity/contracts/ECRecovery.sol";

/**
 * @title Virtual bank smart contract. Support RSMC and HTLC commitments.
 * @dev Simulate the lightning network clearing protocol with Solidity programming language.
 */
contract VirtualBank {
    using SafeMath for uint256;
    using ECRecovery for bytes32;

    string[2] constant NAMES = [string("Alice"), "Bob"];

    struct Client {
        address addr;   // Alice's and Bob's addresses
        uint256 amount;      // amount of each account
        bool    deposited;   // whether each account deposit enough fund
    }

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

    // balance sheets
    Client[2] _clients;

    // state of virtual bank
    State _state;

    // commitment data
    Commitment _commitment;

    // Event for Virtual Bank State Transition
    event VirtualBankFunding(address alice, uint256 amountAlice, address bob, uint256 amountBob);

    event VirtualBankRunning(address alice, uint256 amountAlice, address bob, uint256 amountBob);

    event VirtualBankAuditing();

    event VirtualBankClosed();

    // Event for Fund deposit, Freeze and Withdraw
    event Deposit(string name, address addr, uint256 amountAlice);

    event FreezeFidelityBond(uint sequence, string attackerName, uint256 amount, address revocationLock, unit expireTime);

    event Withdraw(uint sequence, string recipient, address addr, uint256 amount);

    // Event for Commitment Message
    event CommitmentRSMC(uint sequence, string attacker, 
                        uint256 amountAlice, uint256 amountBob, address revocationLock, uint requestTime, uint freezeTime);

    event RevocationLockOpened(uint sequence, unit requestTime, address revocationLock);

    event CommitmentHTLC(uint sequence, string attacker, 
                        uint256 amountAliceRSMC, uint256 amountBobRSMC, address revocationLock, uint requestTime, uint freezeTime, 
                        bytes32 hashLock,  bytes preimage, uint timeLock, uint amountAliceHTLC, unit amountBobHTLC);

    event TimeLockExpire(uint sequence, unit requestTime, unit timeLock);

    event HashLockOpened(address virtualBank, uint sequence, bytes32 hashLock,  bytes preimage, unit time);

    modifier isFunding() {
        require(state == State.Funding,"Should be in Funding state.");
        _;
    }

    modifier isRunning() {
        require(state == State.Running,"Should be in Running state.");
        _;
    }

    modifier isAuditing() {
        require(state == State.Auditing,"Should be in Auditing state.");
        _;
    }

    modifier validAddress(address addr) {
        require(addr != address(0),"address should not be null.");
        _;
    }

    modifier onlyAttacker(address addr) {
        require(addr == _clients[_commitment.attacker].addr, "Only attacker can make this call.");
        _;
    }

    modifier onlyDefender(address addr) {
        require(addr == _clients[1 - _commitment.attacker].addr, "Only defender can make this call.");
        _;
    }

    /**
     * @notice The contructor of virtual bank smart contract
     * @param addrs  Addresses of Alice and Bob
     * @param amount Balance amount of Alice and Bob
     */
    constructor(address[2] addrs, uint256[2] amounts) public validAddress(addrs[0])  validAddress(addrs[1]){
        Client alice = Client(addrs[0], amounts[0], false);
        Client bob   = Client(addrs[1], amounts[1], false);
        _clients = [Client(alice), bob];

        _commitment = Commitment(0, 0, address(0), 0, 0, new uint256[](2));
        _state = State.Funding;
        emit VirtualBankFunding(alice.addr, alice.amount, bob.addr, bob.amount);
    }

    /**
     * @notice Alice or Bob deposit fund to virtual bank.
     */
    function deposit()  external payable isFunding() {

        if(msg.sender == _clients[0].addr && msg.value == _clients[0].amount && !_clients[0].deposited) {
            _clients[0].deposited = true;
            emit Deposit("Alice", msg.sender, msg.value);

        } else if (msg.sender == _clients[1].addr && msg.value == _clients[1].amount && !_clients[1].deposited) {
            _clients[1].deposited = true;
            emit Deposit("Bob", msg.sender, msg.value);

        } else {
            throw;
        }

        // If both Alice and Bob have deposited fund, virtual bank begin running.
        if (_clients[0].deposited && _clients[1].deposited) {
            _state = State.Running;
            emit VirtualBankRunning(_clients[0].addr, _clients[0].amount, _clients[1].addr, _clients[1].amount);
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
    function cashRsmc(uint32 sequence, uint256[2] amounts, address revocationLock, uint freezeTime, bytes defenderSignature) 
                external isRunning() validAddress(revocationLock) {

        require((amounts[0] + amounts[1]) == (_clients[0].amount + _clients[1].amount), "Total amount doesn't match.");

        // identify attacker's index
        uint8 attacker = findAttacker();
        uint8 defender = 1 - attacker;

        // check defender's signature over sequence, revocation lock, new balance sheet, freeze time
        bytes32 msgHash = keccak256(abi.encodePacked(address(this), sequence, amounts[0], amounts[1], revocationLock, freezeTime));
        require(checkSignature(msgHash, defenderSignature, _clients[defender].addr));
        
        uint requestTime = now;

        emit CommitmentRSMC(sequence, NAMES[attacker], amounts[0], amounts[1], revocationLock, requestTime, freezeTime);

        _doCommitment(sequence, attacker, amounts, revocationLock, requestTime, freezeTime);
    }

    /**
     * @notice Virtual bank cash a HTLC commitment which is submitted by Alice or Bob.
     * @param sequence          The sequence number of the commitment.
     * @param rsmcAmounts       Virtual bank settle fund according to this balance sheet if HTLC time lock expire.
     * @param revocationLock    The revocation lock for attacker's findelity bond.
     * @param freezeTime        The freeze time for attacker's findelity bond.
     * @param hashLock          The hash lock in HTLC commitment.
     * @param preimage          The pre-image for the hash lock.
     * @param timeLock          The time lock in HTLC commitment.
     * @param htlcAmounts       Virtual bank settle fund according to this balance sheet if both time lock and hash lock are satisfied.
     * @param defenderSignature The defender's signature.
     */
    function cashHtlc(uint32  sequence,        uint256[2] rsmcAmounts, 
                  address revocationLock,  uint       freezeTime, 
                  bytes32 hashLock;        bytes      preimage;
                  uint    timeLock;        uint[2]    htlcAmounts;
                  bytes   defenderSignature) 
            external isRunning() validAddress(revocationLock){

        // check rsmcAmounts
        require((rsmcAmounts[0] + rsmcAmounts[1]) == (_clients[0].balance + _clients[1].balance), "rsmcAmounts total amount doesn't match.");

        // check htlcAmounts
        require((htlcAmounts[0] + htlcAmounts[1]) == (_clients[0].balance + _clients[1].balance), "htlcAmounts total amount doesn't match.");

        // identify attacker's index
        uint8 attacker = findAttacker();
        uint8 defender = 1- attacker;

        // check defender signature over parameters
        bytes32 msgHash = keccak256(abi.encodePacked(address(this), sequence, rsmcAmounts[0], rsmcAmounts[1], revocationLock, freezeTime, hashLock, timeLock, htlcAmounts[0], htlcAmounts[1]));
        require(checkSignature(msgHash, defenderSignature, _clients[defender].addr));
 
        uint requestTime = now;

        emit CommitmentHTLC(sequence, NAMES[attacker], 
                            rsmcAmounts[0], rsmcAmounts[1], revocationLock, requestTime, freezeTime,
                            hashLock, preimage, timeLock, htlcAmounts[0], htlcAmounts[1]);

        // check time lock
        if (requestTime >= timeLock){
            emit TimeLockExpire(sequence, requestTime, timeLock);

            // if time lock expire, handle this commitment as RSMC
            _doCommitment(sequence, attacker, rsmcAmounts, revocationLock, requestTime, freezeTime);

        } else if {
            // check msgHash lock
            require (keccak256(preimage) == hashLock);
            emit HashLockOpened(address(this), sequence, hashLock, preimage, requestTime);

            // if both time lock and hash lock are satisfied, handle this commitment as HTLC
            _doCommitment(sequence, attacker, htlcAmounts, revocationLock, requestTime, freezeTime);
        }
    }

    /**
     * @notice After freezing time, attacker withdraws his fidelity bond.
     */
    function withdrawByAttacker() external isAuditing() onlyAttacker(msg.sender) {

        require(now >= _commitment.requestTime + _commitment.freezeTime);

        state = State.Closed;
        emit VirtualBankClosed();

        // send fidelity bond back to attacker
        uint attacker = _commitment.attacker;
        uint256 amount = _commitment.amounts[attacker];
        msg.sender.send(amount);
        emit Withdraw(sequence, NAMES[attacker], msg.sender, amount);
    }

    /**
     * @notice Defender solve the revocation lock, withdraws attacker's fidelity bond as penalty.
     * @param revocationSignature  Defender's signature to open the revocation lock.
     */
    function withdrawByDefender(bytes revocationSignature) external isAuditing() onlyDefender(msg.sender) {
        uint attacker = _commitment.attacker;
        uint defender = 1 - attacker;

        // check signature for revocation lock
        bytes32 msgHash = keccak256(abi.encodePacked(address(this), _commitment.sequence));
        require(checkSignature(msgHash, revocationSignature, _commitment.revocationLock));
        emit RevocationLockOpened( _commitment.sequence, now, _commitment.revocationLock);

        // Close virtual bank;
        state = State.Closed;
        emit VirtualBankClosed();

        // send fidelity bond to defender
        uint256 amount = _commitment.amounts[attacker];
        msg.sender.send(amount);
        emit Withdraw(sequence, NAMES[defender], msg.sender, amount);
    }

    /**
     * @notice Virtual bank settle defender's fund immediately, and freeze the attacker's fund as fidelity bond.
     * @param sequence          The sequence number of the commitment.
     * @param attacker          The attacker's index.
     * @param amounts           Virtual bank settle fund according to this balance sheet
     * @param revocationLock    The revocation lock for attacker's findelity bond.
     * @param requestTime       The time when virtual bank recieves the commitment, ie. the start time of fidelity bond freezing.
     * @param freezeTime        How long attacker's findelity bond will be freezed.
     */
    function _doCommitment(uint32 sequence, uint8 attacker, uint256[2] amounts, address revocationLock, uint requestTime, uint freezeTime) internal {
        _commitment.sequence = sequence;
        _commitment.attacker = attacker;
        _commitment.revocationLock = revocationLock;
        _commitment.requestTime = requestTime;
        _commitment.freezeTime = freezeTime;
        _commitment.amounts[0] = amounts[0];
        _commitment.amounts[1] = amounts[1];

        state = State.Auditing;
        emit VirtualBankAuditing();

        // send fund to defender now
        uint8 defender = 1 - attacker;
        _clients[defender].addr.send(amounts[defender]);

        emit Withdraw(sequence, NAMES[defender], _clients[defender].addr, amounts[defender]);
        emit FreezeFidelityBond(sequence, NAMES[attacker], amounts[attacker], revocationLock, requestTime + freezeTime);
    }

    /**
     * @notice find the attacker's index according the sender's address
     * @return 0 for Alice, and 1 for Bob
     */
    function findAttacker() internal view returns (uint8 attacker) {
        if (msg.sender == _clients[0].addr) {
            attacker = 0;
        } else (msg.sender == _clients[1].addr) {
            attacker = 1;
        } else {
            throw;
        }
    }

    /**
     * @notice Check signture.
     * @param msgHash          Message hashs
     * @param signature     Signature bytes      
     * @param expectedAddr  expected address
     * @return If the signature match the expected address.
     */
    function checkSignature( bytes32 msgHash, bytes signature, address expectedAddr) internal pure returns (bool){

        //bytes32 msgHash = keccak256(abi.encodePacked(owner, amount, nonce));
        bytes32 messageHash = msgHash.toEthSignedMessageHash();

        // Verify that the message's signer is the owner of the order
        address signer = messageHash.recover(signature);
        return (signer == expectedAddr);
    }
}