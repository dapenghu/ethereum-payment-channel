pragma solidity ^0.5.1;

import "./lib/external/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./lib/external/openzeppelin-solidity/contracts/AddressUtils.sol";
import "./lib/external/openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "./lib/external/openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";

contract VirtualBank {
    struct Client {
        address addr;
        uint balance; // 余额
        bool deposited; // 是否足额存款
    }

    // 用户列表
    Client[] customers;
    
    // 锁定期限
    int lockPeriod;

    // 状态: init, running, redemption, closed
    int state;

    // 清算人
    int master;

    // 清算时间
    int clearingTime;

    // 清算人赎回公钥
    bytes32 redepmtionPubKey;

    // 构造函数，初始化参数Client[]， state
    constructor(address a, address b, int valuea, int valueb){
    }

    function deposit() payable {
        require(state == init);

        if(msg.sender == customers[0].addr && msg.value == customers[0].balance && !customers[0].deposited) {
            customers[0].deposited = true;
        } else if (msg.sender == customers[1].addr && msg.value == customers[1].balance && !customers[1].deposited) {
            customers[1].deposited = true;
        } else {
            throw;
        }

        if (customers[0].deposited && customers[1].deposited) {
            state = running;
        }
    }

    // 资产清算，
    // 输入参数: 最后的资产负债表，清算人的新地址, 双方的签名
    // 确定清算负责人，优先赎回权。
    function claim() {
        require(state == running)

        // check both signatures

        // 确定清算人的index
        master = ;
        clearingTime = NOW;
        state = redemption;
        redepmtionPubKey = ;

        // 资产分配
        int value = customers[1 - master].balance;
        customers[1 - master].balance = 0;
        customers[1 - master].addr.send(value);

    }

    // 由清算人发起请求，锁定期限之后可以赎回属于自己的资产
    function withdrawByRedemption() {
        require(state == redemption);
        require(msg.sender == customers[master].addr);
        require(NOW >= clearingTime);

        // update state;
        state = closed;
        int value = customers[master].balance;
        customers[master].balance = 0;

        // transfer value 
        customers[master].addr.send(value);
    }

    // 其它股东赎回，携带双方的赎回地址的签名，不需要时间限制
    function withdrawByPeer() {
        require(state == redemption);
        require(msg.sender == customers[1 - master].addr);
        // check signature of redepmtionPubKey

        // update status
        state = closed;
        int value = 
    }
}