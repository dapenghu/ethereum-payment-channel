pragma solidity ^0.5.1;

import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "zeppelin-solidity/contracts/AddressUtils.sol";
import "zeppelin-solidity/contracts/ECRecovery.sol";

contract VirtualBank {
    using SafeMath for uint256;
    using ECRecovery for bytes32;
    using AddressUtils for address;

    struct Client {
        address addr;
        uint balance; // 余额
        bool deposited; // 是否足额存款
    }

    struct Liquidation {
        int32 lockPeriod;   // 锁定期限
        int32 liquidateTime;  // 清盘时间
        address waiverAddr;  // 豁免地址
        int   master;        // 0 or 1. the index of the person who 
        int   nounce;
    }

    // state of VirtualBank contract
    enum State { Funding, Running, Liquidating, Closed }

    // balance sheet
    Client[] _balanceSheet;

    // liquidation information
    Liquidation _liquidation;

    State _state;

    // 构造函数，初始化参数Client[]， state
    constructor(address[] addrs, int[] balances, int32 lockPeriod){
        require(addrs.length == 2);
        require(addrs[0] != address(0) && addrs[1] != address(0));
        require(balances.length == 2);
        require(balances[0] > 0 && balances[1] > 0);
        require(lock > 0);

        _balanceSheet = new Client[2];
        _balanceSheet[0] = Client(addrs[0], balances[0], false);
        _balanceSheet[1] = Client(addrs[1], balances[1], false);

        _liquidation = Liquidation(lock, 0, address(0), 0, 0);
        _state = State.Funding;
    }

    function deposit() payable {
        require(state == State.Funding);

        if(msg.sender == _balanceSheet[0].addr 
         && msg.value == _balanceSheet[0].balance 
         && !_balanceSheet[0].deposited) {
            _balanceSheet[0].deposited = true;

        } else if (msg.sender == _balanceSheet[1].addr 
                 && msg.value == _balanceSheet[1].balance 
                 && !_balanceSheet[1].deposited) {
            _balanceSheet[1].deposited = true;

        } else {
            throw;
        }

        if (_balanceSheet[0].deposited && _balanceSheet[1].deposited) {
            state = running;
        }
    }

    // 资产清算，
    // 输入参数: 最后的资产负债表，清算人的新地址, 双方的签名
    // 确定清算负责人，优先赎回权。
    function liquidate(int nounce, int32[] balances, address waiverAddr, bytes peerSignature) {
        require(state == State.Running)
        require(balances.length == 2);
        require((balances[0] + balances[1]) == (_balanceSheet[0].balance + _balanceSheet[1].balance));
        require(waiverAddr != address(0));

        // identify master liquidator
        int master, peer;
        if (msg.sender == clients[0].addr) {
            master = 0;
            peer = 1;
        } else (msg.sender == clients[1].addr) {
            master = 1;
            peer = 0;
        } else {
            throw;
        }

        // check peer's signature
        bytes32 hash = keccak256(abi.encodePacked(address(this), nounce, balances[0], balances[1], waiverAddr));
        require(checkSignature(hash, peerSignature, _balanceSheet[peer].addr));

        // check new balance sheet
        require(balances[0] > 0 && balances[1] > 0);
        require((balances[0] + balances[1]) == (_balanceSheet[0].balance + _balanceSheet[1].balance));

        // 清盘
        _liquidation.nounce = nounce;
        _liquidation.master = master;
        _liquidation.waiverAddr = waiverAddr;
        _liquidation.liquidateTime = now;

        state = State.Liquidating;

        // 更新资产负债表，将 Peer 的资产返还给Peer，己方的资产留下
        _balanceSheet[master].balance = balances[master];
        _balanceSheet[peer].balance = balances[peer];
        _balanceSheet[peer].addr.send(balances[peer]);

    }

    // 由主清盘人发起请求，锁定期限之后可以赎回属于自己的资产
    function withdrawByMaster() {
        require(state == State.Liquidating);
        int master = _liquidation.master;
        require(msg.sender == _balanceSheet[master].addr);
        require(NOW >= _liquidation.liquidateTime + _liquidation.lockPeriod);

        // update state;
        state = State.Closed;

        // send fund to master
        int value = _balanceSheet[master].balance;
        msg.sender.send(value);
    }

    // 对方股东赎回，携带 Waiver 签名，不需要时间限制
    function withdrawByPeer(int nounce, bytes waiverSignature) {
        require(state == State.Liquidating);
        int peer = 1 - _liquidation.master;
        require(msg.sender == _balanceSheet[peer].addr);

        // check signature of redepmtionPubKey
        bytes32 hash = keccak256(abi.encodePacked(address(this), nounce));
        require(checkSignature(hash, waiverSignature, _liquidation.waiverAddr));

        // update state;
        state = State.Closed;

        // send fund to peer
        int value = _balanceSheet[master].balance;
        _balanceSheet[peer].addr.send(value);
    }

    function checkSignature( bytes32 hash, bytes signature, address expectedAddr) internal pure returns (bool){

        //bytes32 hash = keccak256(abi.encodePacked(owner, amount, nonce));
        bytes32 messageHash = hash.toEthSignedMessageHash();

        // Verify that the message's signer is the owner of the order
        address signer = messageHash.recover(signature);
        require(signer == expectedAddr);
    }
}