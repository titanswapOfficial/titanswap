// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "./interfaces/IWETH.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/ITitanSwapV1Router01.sol";
import "./interfaces/ITitanSwapV1Pair.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/SafeMath.sol";
import "./libraries/TitanSwapV1Library.sol";

interface ITitanSwapV1LimitOrder {

     event Transfer(address indexed from, address indexed to, uint value);

     event Deposit(uint orderId,address indexed pair,address indexed user,uint amountIn,uint amountOut,uint fee);
     // set deposit account address
     function setDepositAccount(address) external;
     function depositExactTokenForTokenOrder(address sellToken,address pair,uint amountIn,uint amountOut) external payable; 
     // deposit swapExactEthForTokens
     function depositExactEthForTokenOrder(address pair,uint amountIn,uint amountOut) external payable;
      // deposit swapExactTokenForETH
     function depositExactTokenForEth(address sellToken,address pair,uint amountIn,uint amountOut) external payable;
     // cancel limit order by orderId
     function cancelTokenOrder(uint orderId) external; 
   
     // execute by swap exact token for token
     function executeExactTokenForTokenOrder(uint orderId, address[] calldata path, uint deadline) external;
     // execute by swap exact eth for token
     function executeExactETHForTokenOrder(uint orderId, address[] calldata path, uint deadline) external payable;
     // execute by swap exact token for eth
     function executeExactTokenForETHOrder(uint orderId, address[] calldata path, uint deadline) external;
      
     
     function queryOrder(uint orderId) external view returns(address,address,uint,uint,uint);
     function existOrder(uint orderId) external view returns(bool);
     function withdrawFee(address payable to) external;
     function setEthFee(uint _ethFee) external;
}

contract TitanSwapV1LimitOrder is ITitanSwapV1LimitOrder {

    using SafeMath for uint;
    address public  depositAccount;
    address public immutable router;
    address public immutable  WETH;
     address public immutable factory;
    uint public balance;
    uint public userBalance;
    mapping (uint => Order) private depositOrders;
    // to deposit order count
    uint public orderCount;
    // total order count
    uint public orderIds;
    // eth fee,defualt 0.01 eth
    uint public ethFee = 10000000000000000;
   
    constructor(address _router,address _depositAccount,address _WETH,address _factory,uint _ethFee) public{
        router = _router;
        depositAccount = _depositAccount;
        WETH = _WETH;
        factory = _factory;
        ethFee = _ethFee;
    }
    
   
    
    struct Order {
        bool exist;
        address pair;
        address payable user; // 用户地址
        address sellToken;
        // uint direct; // 0 或 1,默认根据pair的token地址升序排,0- token0, token1 1- token1 token0
        uint amountIn;
        uint amountOut;
        uint ethValue;
       
    }
    
     function setDepositAccount(address _depositAccount)  external override{
        require(msg.sender == depositAccount, 'TitanSwapV1: FORBIDDEN');
        depositAccount = _depositAccount;
    }
    

    function depositExactTokenForTokenOrder(address sellToken,address pair,uint amountIn,uint amountOut) external override payable {
        // call swap method cost fee.
        uint fee = ethFee;
        require(msg.value >= fee,"TitanSwapV1 : no fee enough");
        orderIds = orderIds.add(1);
        uint _orderId = orderIds;
        // need transfer eth fee. need msg.sender send approve trx first.
        TransferHelper.safeTransferFrom(sellToken,msg.sender,address(this),amountIn);
       
        depositOrders[_orderId] = Order(true,pair,msg.sender,sellToken,amountIn,amountOut,msg.value);
        emit Deposit(_orderId,pair,msg.sender,amountIn,amountOut,msg.value);
        orderCount = orderCount.add(1);
        balance = balance.add(msg.value);
        userBalance = userBalance.add(msg.value);
    }
    
     function depositExactEthForTokenOrder(address pair,uint amountIn,uint amountOut) external override payable {
        uint fee = ethFee;
        uint calFee = msg.value.sub(amountIn);
        require(calFee >= fee,"TitanSwapV1 : no fee enough");
        
        orderIds = orderIds.add(1);
        uint _orderId = orderIds;
        
        depositOrders[_orderId] = Order(true,pair,msg.sender,address(0),amountIn,amountOut,msg.value);
        emit Deposit(_orderId,pair,msg.sender,amountIn,amountOut,msg.value);
        orderCount = orderCount.add(1);
        balance = balance.add(msg.value);
        userBalance = userBalance.add(msg.value);
     }
     
      function depositExactTokenForEth(address sellToken,address pair,uint amountIn,uint amountOut) external override payable {
        uint fee = ethFee;
        require(msg.value >= fee,"TitanSwapV1 : no fee enough");
        orderIds = orderIds.add(1);
        uint _orderId = orderIds;
        
         // need transfer eth fee. need msg.sender send approve trx first.
        TransferHelper.safeTransferFrom(sellToken,msg.sender,address(this),amountIn);
        depositOrders[_orderId] = Order(true,pair,msg.sender,sellToken,amountIn,amountOut,msg.value);
        emit Deposit(_orderId,pair,msg.sender,amountIn,amountOut,msg.value);
        orderCount = orderCount.add(1);
        balance = balance.add(msg.value);
        userBalance = userBalance.add(msg.value);
      }
     
     
     
    
    function cancelTokenOrder(uint orderId) external override {
        Order memory order = depositOrders[orderId];
        require(order.exist,"order not exist.");
        require(msg.sender == order.user,"no auth to cancel.");
        
        // revert eth
        TransferHelper.safeTransferETH(order.user,order.ethValue);
        
        if(order.sellToken != address(0)) {
            // revert token
            TransferHelper.safeTransfer(order.sellToken,order.user,order.amountIn);
        }
        
        userBalance = userBalance.sub(order.ethValue);
        balance = balance.sub(order.ethValue);
        
        delete(depositOrders[orderId]);
        orderCount = orderCount.sub(1);
    }
    
    function queryOrder(uint orderId) external override view returns(address,address,uint,uint,uint) {
        Order memory order = depositOrders[orderId];
        return (order.pair,order.user,order.amountIn,order.amountOut,order.ethValue);
    }
    
    function existOrder(uint orderId) external override view returns(bool) {
        return depositOrders[orderId].exist;
    }
    
     function executeExactTokenForTokenOrder(
        uint orderId,
        address[] calldata path,
        uint deadline
   ) external override {
       require(msg.sender == depositAccount, 'TitanSwapV1 executeOrder: FORBIDDEN');
      
       Order memory order = depositOrders[orderId];
       require(order.exist,"order not exist!");
       // approve to router 
       TransferHelper.safeApprove(path[0],router,order.amountIn);
   
       
       delete(depositOrders[orderId]);
       orderCount = orderCount.sub(1);
       userBalance = userBalance.sub(order.ethValue);
       
       ITitanSwapV1Router01(router).swapExactTokensForTokens(order.amountIn,order.amountOut,path,order.user,deadline);
    }
    
     // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = TitanSwapV1Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? TitanSwapV1Library.pairFor(factory, output, path[i + 2]) : _to;
            ITitanSwapV1Pair(TitanSwapV1Library.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    
    
    function executeExactETHForTokenOrder(uint orderId, address[] calldata path, uint deadline) external override payable {
          require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
         require(msg.sender == depositAccount, 'TitanSwapV1 executeOrder: FORBIDDEN');
         require(msg.value > 0, 'TitanSwapV1 executeOrder: NO ETH');
        Order memory order = depositOrders[orderId];
        require(order.exist,"order not exist!");
        delete(depositOrders[orderId]);
        orderCount = orderCount.sub(1);
        userBalance = userBalance.sub(order.ethValue);
        // call with msg.value = amountIn
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        uint[]  memory amounts = TitanSwapV1Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= order.amountOut, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        
        IWETH(WETH).deposit{value: msg.value}();
         assert(IWETH(WETH).transfer(order.pair, amounts[0]));
        _swap(amounts, path, order.user);
        
    }
    
    
    function executeExactTokenForETHOrder(uint orderId, address[] calldata path, uint deadline) external override {
         require(msg.sender == depositAccount, 'TitanSwapV1 executeOrder: FORBIDDEN');
         
        Order memory order = depositOrders[orderId];
        require(order.exist,"order not exist!");
        // approve to router 
        TransferHelper.safeApprove(path[0],router,order.amountIn);
        delete(depositOrders[orderId]);
        orderCount = orderCount.sub(1);
        userBalance = userBalance.sub(order.ethValue);
        ITitanSwapV1Router01(router).swapExactTokensForETH(order.amountIn,order.amountOut,path,order.user,deadline);
    }
    
    
    function withdrawFee(address payable to) external override {
        require(msg.sender == depositAccount, 'TitanSwapV1 : FORBIDDEN');
        uint amount = balance.sub(userBalance);
        require(amount > 0,'TitanSwapV1 : amount = 0');
        TransferHelper.safeTransferETH(to,amount);
        balance = balance.sub(amount);
    }
    
    function setEthFee(uint _ethFee) external override {
        require(msg.sender == depositAccount, 'TitanSwapV1 : FORBIDDEN');
        require(_ethFee >= 10000000,'TitanSwapV1: fee wrong');
        ethFee = _ethFee;
    }


}


