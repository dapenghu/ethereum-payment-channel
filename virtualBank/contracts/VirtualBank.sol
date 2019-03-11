pragma solidity ^0.5.1;

import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "zeppelin-solidity/contracts/AddressUtils.sol";
import "zeppelin-solidity/contracts/ECRecovery.sol";

contract VirtualBank {
    using SafeMath for uint256;
    using ECRecovery for bytes32;
//    using AddressUtils for address;

    struct BalanceSheet {
        address[2] addresses;   // Alice's and Bob's addresses
        uint256[2] amount;      // amount of each account
        bool[2]    deposited;   // whether each account deposit enough fund
    }

    struct Commitment {
        uint32     sequence;
        uint8      attacker;      // defender = 1 - attacker
        address    revocationLock;
        uint       maturityTime;
        uint       requestTime;
        uint256[2] amounts;        // amount[attacker] is fidelity bond
    }

    // state of VirtualBank contract
    enum State { Funding, Running, Auditing, Closed }

    // balance sheet
    BalanceSheet _balanceSheet;

    State _state;

    Commitment _commitment;

    // 构造函数，初始化参数Client[]， state
    constructor(address[2] addrs, uint256[2] amounts){
        require(addrs[0] != address(0) && addrs[1] != address(0));

        _balanceSheet.addresses = [addrs[0], addrs[1]];
        _balanceSheet.amount = [amounts[0], amounts[1]];
        _balanceSheet.deposited = [bool(false), false];

        _liquidation = Liquidation(lock, 0, address(0), 0, 0);
        _state = State.Funding;
    }

    function deposit() payable {
        require(state == State.Funding);

        if(msg.sender == _balanceSheet.addresses[0]
         && msg.value == _balanceSheet.amount[0]
         && !_balanceSheet.deposited[0]) {
            _balanceSheet.deposited[0] = true;

        } else if (msg.sender == _balanceSheet.addresses[1]
                && msg.value == _balanceSheet.amount[1]
                && !_balanceSheet.deposited[1]) {
            _balanceSheet.deposited[1] = true;

        } else {
            throw;
        }

        if (_balanceSheet.deposited[0] && _balanceSheet.deposited[1]) {
            _state = State.Running;
        }
    }

    // 资产清算，
    // 输入参数: 最后的资产负债表，清算人的新地址, 双方的签名
    // 确定清算负责人，优先赎回权。
    function rsmc(uint32 sequence, uint256[2] amounts, address revocationLock, 
                  uint maturityTime, bytes defenderSignature) {
        require(state == State.Running)
        require((amounts[0] + amounts[1]) == (_balanceSheet[0].balance + _balanceSheet[1].balance));
        require(revocationLock != address(0));

        // identify attacker
        uint8 attacker = findAttacker();
        uint8 defender = 1 - attacker;

        // check defender's signature over sequence, revocation lock, new balance sheet, maturity time
        bytes32 hash = keccak256(abi.encodePacked(address(this), sequence, amounts[0], amounts[1], revocationLock, maturityTime));
        require(checkSignature(hash, defenderSignature, _balanceSheet[defender].addr));

        _doCommitment(sequence, amounts, revocationLock, maturityTime, attacker);
    }

    // 由主清盘人发起请求，锁定期限之后可以赎回属于自己的资产
    function withdrawByAttacker() {
        require(state == State.Auditing);

        int master = _liquidation.master;
        require(msg.sender == _balanceSheet[master].addr);
        require(now >= _liquidation.requestTime + _liquidation.maturityTime);

        // update state;
        state = State.Closed;

        // send fidelity bond to attacker
        int value = _balanceSheet[master].balance;
        msg.sender.send(value);
    }

    // 对方股东赎回，携带 Waiver 签名，不需要时间限制
    function withdrawByDefender(bytes revocationSignature) {
        require(state == State.Liquidating);
        int peer = 1 - _liquidation.master;
        require(msg.sender == _balanceSheet[peer].addr);

        // check signature of redepmtionPubKey
        bytes32 hash = keccak256(abi.encodePacked(address(this), nounce));
        require(checkSignature(hash, waiverSignature, _liquidation.waiverAddr));

        // update state;
        state = State.Closed;

        // send fidelity bond to defender
        int value = _balanceSheet[master].balance;
        _balanceSheet[peer].addr.send(value);
    }

    function htlc(uint32 sequence,        uint256[2] origAmounts, 
                  address revocationLock, uint maturityTime, 
                  bytes32    hashLock;    bytes      preimage;
                  uint       timeLock;    uint[2]    newAmounts;
                  bytes      defenderSignature) {

        // check defender signature
        // check origAmounts and newAmounts
        // check revocation lock
        // identify attacker
        uint8 attacker = findAttacker();
        uint8 defender = 1- attacker;

        // check time lock
        if (expire){
            _doCommitment(sequence, origAmounts, revocationLock, maturityTime, attacker);

        } else if {
            // check hash lock
            require (preimage match );
            _doCommitment(sequence, newAmounts, revocationLock, maturityTime, attacker);
        }
    }

    function findAttacker() internal view returns (uint8 attacker) {
        if (msg.sender == clients[0].addr) {
            attacker = 0;
        } else (msg.sender == clients[1].addr) {
            attacker = 1;
        } else {
            throw;
        }
    }

    function _doCommitment(uint32 sequence, uint256[2] amounts, address revocationLock, uint maturityTime, uint8 attacker) internal {
        _rsmc = RSMC(sequence, attacker, revocationLock, maturityTime, now, new uint256[](2));
        _rsmc.amounts[0] = amounts[0];
        _rsmc.amounts[1] = amounts[1];

        state = State.Auditing;

        // 结算 Defender 的资产，Attacker 的资产留下作为诚信保证金
        uint8 defender = 1 - attacker;
        _balanceSheet[defender].addr.send(balances[defender]);
    }

    function checkSignature( bytes32 hash, bytes signature, address expectedAddr) internal pure returns (bool){

        //bytes32 hash = keccak256(abi.encodePacked(owner, amount, nonce));
        bytes32 messageHash = hash.toEthSignedMessageHash();

        // Verify that the message's signer is the owner of the order
        address signer = messageHash.recover(signature);
        require(signer == expectedAddr);
    }
}