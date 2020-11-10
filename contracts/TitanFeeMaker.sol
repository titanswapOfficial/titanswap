pragma solidity =0.6.12;

import "./interfaces/ITitanSwapV1Pair.sol";
import "./interfaces/Ownable.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/ITitanFeeMaker.sol";
import "./libraries/SafeMath.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/TitanSwapV1Library.sol";
import "./interfaces/ITitanSwapV1Factory.sol";


contract TitanFeeMaker is Ownable,ITitanFeeMaker{
    using SafeMath for uint256;

    ITitanSwapV1Factory public factory;
    address public weth;
    address public titan;
    address public usdt;
    address public routerAddress;

    // Bonus muliplier for early sushi makers.
    uint256 public BONUS_MULTIPLIER = 100;
    // Bonus muliplier for early sushi makers.
    uint256 public constant BONUS_BASE_RATE = 100;
    // record need reward titan amount
    uint256 public titanRewardAmount = 0;
    // recod already transfer titan reward
    uint256 public titanRewardAmountAlready = 0;


    // Info of each lp pool
    struct PoolInfo {
        address lpToken;
        uint256 lastRewardBlock;
        uint256 accTitanPerShare;
    }

    // Info of each user;
    struct UserInfo {
        uint256 amount; // How many lp tokens the user has provided;
        uint256 rewardDebt; // Reward debt;
    }

    // info of lp pool
    mapping (address => PoolInfo) public poolInfo;
    mapping (address => mapping(address => UserInfo)) public userInfo;

    // add this function to receive eth
    receive() external payable {
        assert(msg.sender == weth); // only accept ETH via fallback from the WETH contract
    }

    constructor(ITitanSwapV1Factory _factory,address _routerAddress,address _titan,address _weth,address _usdt) public {
        factory = _factory;
        titan = _titan;
        weth = _weth;
        usdt = _usdt;
        routerAddress = _routerAddress;
    }

    event createPool(address indexed lpToken,uint256 blockNumber);


    // Update reward variables of the given pool;
    function updatePool(address _lpToken,uint256 _addLpAmount) private {
        PoolInfo storage pool =  poolInfo[_lpToken];
        // create pool
        if(pool.lastRewardBlock == 0) {
            poolInfo[_lpToken] = PoolInfo({
            lpToken: _lpToken,
            lastRewardBlock: block.number,
            accTitanPerShare: 0
            });
            pool = poolInfo[_lpToken];
            emit createPool(_lpToken,block.number);
        }

        if(block.number < pool.lastRewardBlock) {
            return;
        }

        pool.lastRewardBlock = block.number;
        uint256 feeLpBalance = ITitanSwapV1Pair(pool.lpToken).balanceOf(address(this));
        if(feeLpBalance == 0) {
            return;
        }
        uint256 titanFeeReward = convertLpToTitan(ITitanSwapV1Pair(pool.lpToken),feeLpBalance);
        if(titanFeeReward == 0) {
            return;
        }
        // maybe reward more
        titanFeeReward = titanFeeReward.mul(BONUS_MULTIPLIER).div(BONUS_BASE_RATE);
        titanRewardAmount = titanRewardAmount.add(titanFeeReward);
        uint256 lpSupply = ITitanSwapV1Pair(pool.lpToken).totalSupply().sub(_addLpAmount);
        pool.accTitanPerShare = pool.accTitanPerShare.add(titanFeeReward.mul(1e18).div(lpSupply));
    }

    // call when add Liquidity，
    function depositLp(address _lpToken,uint256 _amount) external override {
        if(_amount > 0) {
            require(msg.sender == routerAddress,'TitanSwapV1FeeMaker: must call by router');
        }
        updatePool(_lpToken,_amount);
        PoolInfo storage pool = poolInfo[_lpToken];
        UserInfo storage user = userInfo[_lpToken][tx.origin];
        if(user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accTitanPerShare).div(1e18).sub(user.rewardDebt);
            if(pending > 0) {
                require(IERC20(titan).balanceOf(address(this)) >= pending,'TitanSwapV1FeeMaker: titan not enough');
                TransferHelper.safeTransfer(titan,tx.origin,pending);
                titanRewardAmountAlready = titanRewardAmountAlready.add(pending);
            }
        }
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accTitanPerShare).div(1e18);
    }
    // call when remove Liquidity
    function withdrawLp(address _lpToken,uint256 _amount) external override {
        if(_amount > 0) {
            require(msg.sender == routerAddress,'TitanSwapV1FeeMaker: must call by router');
        }
        updatePool(_lpToken,0);
        PoolInfo storage pool = poolInfo[_lpToken];
        UserInfo storage user = userInfo[_lpToken][tx.origin];
        require(user.amount >= _amount,'remove lp not good');
        uint256 pending = user.amount.mul(pool.accTitanPerShare).div(1e18).sub(user.rewardDebt);
        if(pending > 0) {
            require(IERC20(titan).balanceOf(address(this)) >= pending,'TitanSwapV1FeeMaker: titan not enough');
            TransferHelper.safeTransfer(titan,tx.origin,pending);
            titanRewardAmountAlready = titanRewardAmountAlready.add(pending);
        }
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accTitanPerShare).div(1e18);
    }



    function convertLpToTitan(ITitanSwapV1Pair _pair,uint256 _feeLpBalance) private returns(uint256){

        uint256 beforeTitan = IERC20(titan).balanceOf(address(this));
        uint256 beforeWeth = IERC20(weth).balanceOf(address(this));
        uint256 beforeUsdt = IERC20(usdt).balanceOf(address(this));

        _pair.transfer(address(_pair),_feeLpBalance);
        _pair.burn(address(this));

        address token0 = _pair.token0();
        address token1 = _pair.token1();

        if(token0 == weth || token1 == weth) {
            // convert token to weth
            _toWETH(token0);
            _toWETH(token1);
            uint256 wethAmount = IERC20(weth).balanceOf(address(this)).sub(beforeWeth);
            if(token0 == titan || token1 == titan) {
                ITitanSwapV1Pair pair = ITitanSwapV1Pair(factory.getPair(titan,weth));
                (uint reserve0, uint reserve1,) = pair.getReserves();
                address _token0 = pair.token0();
                (uint reserveIn, uint reserveOut) = _token0 == titan ? (reserve0, reserve1) : (reserve1, reserve0);
                uint titanAmount = IERC20(titan).balanceOf(address(this)).sub(beforeTitan);
                uint256 titanWethAmount = reserveOut.mul(titanAmount).div(reserveIn);
                wethAmount = wethAmount.add(titanWethAmount);
            }
            // convert to titan
            return _wethToTitan(wethAmount);
        }

        if(token0 == usdt || token1 == usdt) {
            // convert token to usdt
            _toUSDT(token0);
            _toUSDT(token1);
            uint256 usdtAmount = IERC20(usdt).balanceOf(address(this)).sub(beforeUsdt);
            if(token0 == titan || token1 == titan) {
                ITitanSwapV1Pair pair = ITitanSwapV1Pair(factory.getPair(titan,usdt));
                (uint reserve0, uint reserve1,) = pair.getReserves();
                address _token0 = pair.token0();
                (uint reserveIn, uint reserveOut) = _token0 == titan ? (reserve0, reserve1) : (reserve1, reserve0);
                uint titanAmount = IERC20(titan).balanceOf(address(this)).sub(beforeTitan);
                uint256 titanUsdtAmount = reserveOut.mul(titanAmount).div(reserveIn);
                usdtAmount = usdtAmount.add(titanUsdtAmount);
            }
            // convert to titan
            return _usdtToTitan(usdtAmount);
        }
        return 0;
    }

    function _toUSDT(address token) private returns (uint256) {
        if(token == usdt || token == titan) {
            return 0;
        }
        ITitanSwapV1Pair pair = ITitanSwapV1Pair(factory.getPair(token,usdt));
        if(address(pair) == address(0)) {
            return 0;
        }
        (uint reserve0, uint reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        (uint reserveIn, uint reserveOut) = token0 == token ? (reserve0, reserve1) : (reserve1, reserve0);

        return swapTokenForWethOrUsdt(token,token0,pair,reserveIn,reserveOut);
    }

    function _toWETH(address token) private returns (uint256) {
        if(token == weth || token == titan) {
            return 0;
        }
        ITitanSwapV1Pair pair = ITitanSwapV1Pair(factory.getPair(token,weth));
        if(address(pair) == address(0)) {
            return 0;
        }
        (uint reserve0, uint reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        (uint reserveIn, uint reserveOut) = token0 == token ? (reserve0, reserve1) : (reserve1, reserve0);

        return swapTokenForWethOrUsdt(token,token0,pair,reserveIn,reserveOut);
    }

    function swapTokenForWethOrUsdt(address token,address token0,ITitanSwapV1Pair pair,uint reserveIn,uint reserveOut) private returns (uint256) {
        // contract token balance
        uint amountIn = IERC20(token).balanceOf(address(this));
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        uint amountOut = numerator / denominator;
        (uint amount0Out, uint amount1Out) = token0 == token ? (uint(0), amountOut) : (amountOut, uint(0));
        TransferHelper.safeTransfer(token,address(pair),amountIn);
        // swap token for eth
        pair.swap(amount0Out, amount1Out, address(this), new bytes(0));
        return amountOut;
    }

    function _wethToTitan(uint256 amountIn) internal view returns (uint256) {
        ITitanSwapV1Pair pair = ITitanSwapV1Pair(factory.getPair(titan,weth));
        require(address(pair) != address(0),'TitanSwapV1FeeMaker: titan/eth not exist');
        (uint reserve0, uint reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        (uint reserveIn, uint reserveOut) = token0 == weth ? (reserve0, reserve1) : (reserve1, reserve0);
        return reserveOut.mul(amountIn).div(reserveIn);
    }

    function _usdtToTitan(uint256 amountIn) internal view returns (uint256) {
        ITitanSwapV1Pair pair = ITitanSwapV1Pair(factory.getPair(titan,usdt));
        require(address(pair) != address(0),'TitanSwapV1FeeMaker: titan/usdt not exist');
        (uint reserve0, uint reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        (uint reserveIn, uint reserveOut) = token0 == usdt ? (reserve0, reserve1) : (reserve1, reserve0);
        return reserveOut.mul(amountIn).div(reserveIn);
    }

    function withdrawETH(address to) external override onlyOwner{
        uint256 wethBalance = IERC20(weth).balanceOf(address(this));
        // require(wethBalance > 0,'TitanSwapV1FeeMaker: weth amount == 0');
        IWETH(weth).withdraw(wethBalance);
        TransferHelper.safeTransferETH(to,wethBalance);
        // TransferHelper.safeTransfer(weth,to,wethBalance);
    }

    function withdrawUSDT(address to) external override onlyOwner{
        uint256 usdtBalance = IERC20(usdt).balanceOf(address(this));
        require(usdtBalance > 0,'TitanSwapV1FeeMaker: usdt amount == 0');
        TransferHelper.safeTransfer(usdt,to,usdtBalance);
    }

    function chargeTitan(uint256 _amount) external override {
        TransferHelper.safeTransferFrom(titan,msg.sender,address(this),_amount);
    }

    function withdrawTitan(uint256 _amount) external override onlyOwner {
        uint256 balance = IERC20(titan).balanceOf(address(this));
        require(balance >= _amount,'balance not enough');
        TransferHelper.safeTransfer(titan,msg.sender,_amount);
    }

    function adjustTitanBonus(uint256 _BONUS_MULTIPLIER) external override onlyOwner {
        require(_BONUS_MULTIPLIER >= 100,'number must >= 100');
        BONUS_MULTIPLIER = _BONUS_MULTIPLIER;
    }

}