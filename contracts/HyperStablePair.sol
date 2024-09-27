// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;

import '../interfaces/IHyperStablePair.sol';
import '../libraries/Math.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IHyperStableFactory.sol';
import '../interfaces/IHyperStableCallee.sol';
import './HyperStableERC20.sol';

contract HyperStablePair is IHyperStablePair, HyperStableERC20 {

  bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

  address private factory;
  address private token0;
  address private token1;

  uint private initialized;
  uint private unlocked = 1;

  uint private constant FEE_DENOMINATOR = 100000;
  // uint public constant MAX_FEE_PERCENT = 2000; // = 2%

  uint112 private reserve0;           // uses single storage slot, accessible via getReserves
  uint112 private reserve1;           // uses single storage slot, accessible via getReserves
  uint16 public token0FeePercent = 300; // default = 0.3%  // uses single storage slot, accessible via getReserves
  uint16 public token1FeePercent = 300; // default = 0.3%  // uses single storage slot, accessible via getReserves

  uint private precisionMultiplier0;
  uint private precisionMultiplier1;

  uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

  bool private stableSwap=true; // if set to true, defines pair type as stable
  bool private pairTypeImmutable; // if set to true, stableSwap states cannot be updated anymore

  modifier lock() {
    require(unlocked == 1, 'HyperStable: LOCKED');
    unlocked = 0;
    _;
    unlocked = 1;
  }

  event FeePercentUpdated(uint16 token0FeePercent, uint16 token1FeePercent);
  event SetStableSwap(bool prevStableSwap, bool stableSwap);

  function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint16 _token0FeePercent, uint16 _token1FeePercent) {
    _reserve0 = reserve0;
    _reserve1 = reserve1;
    _token0FeePercent = token0FeePercent;
    _token1FeePercent = token1FeePercent;
  }

  function _safeTransfer(address token, address to, uint value) private {
    (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
    require(success && (data.length == 0 || abi.decode(data, (bool))),"HyperStable: TRANSFER_FAILED");
  }

  constructor() HyperStableERC20() {
    factory = msg.sender;
  }

  function getDecimals(address token)private view returns(uint _decimals){
    _decimals=uint(IERC20(token).decimals());
  }

  // called once by the factory at time of deployment
  function initialize(address _token0, address _token1) external {
    require(msg.sender == factory && initialized==0);
    // sufficient check
    token0 = _token0;
    token1 = _token1;

    precisionMultiplier0 = 10 ** getDecimals(_token0);
    precisionMultiplier1 = 10 ** getDecimals(_token1);

    initialized = 1;
  }

  function getOwner()private view returns(address _owner){
    _owner=IHyperStableFactory(factory).getOwner();
  }

  function getBalance(address token,address checker)private view returns(uint _thisBalance){
    _thisBalance=IERC20(token).balanceOf(checker);
  }

  /**
  * @dev Updates the swap fees percent
  *
  * Can only be called by the factory's feeAmountOwner
  */
  function setFeePercent(uint16 newToken0FeePercent, uint16 newToken1FeePercent) external lock {
    require(msg.sender == getOwner());
    require((newToken0FeePercent > 0 && newToken0FeePercent <= 2000) && (newToken1FeePercent>0 && newToken1FeePercent <= 2000));
    token0FeePercent = newToken0FeePercent;
    token1FeePercent = newToken1FeePercent;
    emit FeePercentUpdated(newToken0FeePercent, newToken1FeePercent);
  }

  function setPairTypeImmutable() external lock {
    require(msg.sender == getOwner());
    require(!pairTypeImmutable, "HyperStable: already immutable");
    pairTypeImmutable = true;
  }

  function setStableSwap(bool stable, uint112 expectedReserve0, uint112 expectedReserve1) external lock {
    require(msg.sender == IHyperStableFactory(factory).getStableOwner());
    require(!pairTypeImmutable, "HyperStable: immutable");
    require(stable != stableSwap);
    require(expectedReserve0 == reserve0 && expectedReserve1 == reserve1, "HyperStable: failed");
    emit SetStableSwap(stableSwap, stable);
    stableSwap = stable;
  }

  // update reserves
  function _update(uint balance0, uint balance1) private {
    require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "HyperStable: OVERFLOW");
    reserve0 = uint112(balance0);
    reserve1 = uint112(balance1);
    emit Sync(uint112(balance0), uint112(balance1));
  }

  // this low-level function should be called from a contract which performs important safety checks
  function mint(address to) external lock returns (uint liquidity) {
    (uint112 _reserve0, uint112 _reserve1,,) = getReserves();
    // gas savings
    uint balance0 = getBalance(token0,address(this));
    uint balance1 = getBalance(token1,address(this));
    uint amount0 = balance0-_reserve0;
    uint amount1 = balance1-_reserve1;

    uint _totalSupply = totalSupply;
    // gas savings, must be defined here since totalSupply can update in _mintFee
    if (_totalSupply == 0) {
      //MINIMUM_LIQUIDITY=1000
      liquidity = Math.sqrt(amount0*amount1)-1000;
      _mint(address(0), 1000);
      // permanently lock the first MINIMUM_LIQUIDITY tokens
    } else {
      liquidity = Math.min(amount0*_totalSupply / _reserve0, amount1*_totalSupply / _reserve1);
    }
    require(liquidity > 0, "HyperStable: INSUFFICIENT_LIQUIDITY_MINTED");
    _mint(to, liquidity);

    _update(balance0, balance1);
    // reserve0 and reserve1 are up-to-date
    emit Mint(msg.sender, amount0, amount1);
  }

  // this low-level function should be called from a contract which performs important safety checks
  function burn(address to) external lock returns (uint amount0, uint amount1) {
    address _token0 = token0; // gas savings
    address _token1 = token1; // gas savings
    uint balance0 = getBalance(_token0,address(this));
    uint balance1 = getBalance(_token1,address(this));
    uint liquidity = balanceOf[address(this)];

    uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
    amount0 = liquidity*balance0 / _totalSupply; // using balances ensures pro-rata distribution
    amount1 = liquidity*balance1 / _totalSupply; // using balances ensures pro-rata distribution
    require(amount0 > 0 && amount1 > 0, "HyperStable: INSUFFICIENT_LIQUIDITY_BURNED");
    _burn(address(this), liquidity);
    _safeTransfer(_token0, to, amount0);
    _safeTransfer(_token1, to, amount1);
    balance0 = getBalance(_token0,address(this));
    balance1 = getBalance(_token1,address(this));

    _update(balance0, balance1);
    emit Burn(msg.sender, amount0, amount1, to);
  }

  // this low-level function should be called from a contract which performs important safety checks
  function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external {
    TokensData memory tokensData = TokensData({
      token0: token0,
      token1: token1,
      amount0Out: amount0Out,
      amount1Out: amount1Out,
      balance0: 0,
      balance1: 0,
      remainingFee0: 0,
      remainingFee1: 0
    });
    _swap(tokensData, to, data);
  }

  function _swap(TokensData memory tokensData, address to, bytes memory data) internal lock {
    require(tokensData.amount0Out > 0 || tokensData.amount1Out > 0, "HyperStable: INSUFFICIENT_OUTPUT_AMOUNT");

    (uint112 _reserve0, uint112 _reserve1, uint16 _token0FeePercent, uint16 _token1FeePercent) = getReserves();
    require(tokensData.amount0Out < _reserve0 && tokensData.amount1Out < _reserve1, "HyperStable: INSUFFICIENT_LIQUIDITY");

    {
      require(to != tokensData.token0 && to != tokensData.token1, "HyperStable: INVALID_TO");
      //send receive
      // optimistically transfer tokens
      if (tokensData.amount0Out > 0) _safeTransfer(tokensData.token0, to, tokensData.amount0Out);
      // optimistically transfer tokens
      if (tokensData.amount1Out > 0) _safeTransfer(tokensData.token1, to, tokensData.amount1Out);
      if (data.length > 0) IHyperStableCallee(to).uniswapV2Call(msg.sender, tokensData.amount0Out, tokensData.amount1Out, data);
      tokensData.balance0 = getBalance(tokensData.token0,address(this));
      tokensData.balance1 = getBalance(tokensData.token1,address(this));
    }

    uint amount0In = tokensData.balance0 > _reserve0 - tokensData.amount0Out ? tokensData.balance0 - (_reserve0 - tokensData.amount0Out) : 0;
    uint amount1In = tokensData.balance1 > _reserve1 - tokensData.amount1Out ? tokensData.balance1 - (_reserve1 - tokensData.amount1Out) : 0;
    require(amount0In > 0 || amount1In > 0, "HyperStable: INSUFFICIENT_INPUT_AMOUNT");

    tokensData.remainingFee0 = amount0In*_token0FeePercent / FEE_DENOMINATOR;
    tokensData.remainingFee1 = amount1In*_token1FeePercent / FEE_DENOMINATOR;

    {// scope for stable fees management
      uint fee = 0;
      if(stableSwap){
        address feeTo = IHyperStableFactory(factory).feeInfo();
        if(feeTo != address(0)){
          if (amount0In > 0) {
            fee = amount0In*_token0FeePercent / FEE_DENOMINATOR;
            tokensData.remainingFee0 = tokensData.remainingFee0-fee;
            //Official fee
            _safeTransfer(tokensData.token0, feeTo, fee);
          }
          if (amount1In > 0) {
            fee = amount1In*_token1FeePercent / FEE_DENOMINATOR;
            tokensData.remainingFee1 = tokensData.remainingFee1-fee;
            //Official fee
            _safeTransfer(tokensData.token1, feeTo, fee);
          }
        }
      }

      // readjust tokens balance
      if (amount0In > 0) tokensData.balance0 = getBalance(tokensData.token0,address(this));
      if (amount1In > 0) tokensData.balance1 = getBalance(tokensData.token1,address(this));
    }
    {// scope for reserve{0,1}Adjusted, avoids stack too deep errors
      uint balance0Adjusted = tokensData.balance0-tokensData.remainingFee0;
      uint balance1Adjusted = tokensData.balance1-tokensData.remainingFee1;
      require(_k(balance0Adjusted, balance1Adjusted) >= _k(uint(_reserve0), uint(_reserve1)));
    }
    _update(tokensData.balance0, tokensData.balance1);
    emit Swap(msg.sender, amount0In, amount1In, tokensData.amount0Out, tokensData.amount1Out, to);
  }

  //x^{3}y+xy^{3}+1.618*x^{2}*y^{2}=k
  function _k(uint balance0, uint balance1) public view returns (uint) {
    if (stableSwap) {
      uint _x = balance0 / precisionMultiplier0 * 1e18 ;
      uint _y = balance1 / precisionMultiplier1 * 1e18 ;
      uint _r1 = 1e18 / precisionMultiplier0;
      uint _r2 = 1e18 / precisionMultiplier1;
      uint _a = (_x*_y) / (_r1*_r2);
      uint _b = (_x*_x) / (_r1*_r1)+(_y*_y) / (_r2*_r2);
      uint _i = 1618 * _x / 1000 * _x / (_r1*_r1);
      uint _j = _y * _y / (_r2*_r2);
      return  _a*_b+_i*_j; // x^3*y+y^3*x+1.618*x^2*y^2 >= k
    }else{
      return balance0*balance1;
    }
  }

  // function _k(uint balance0, uint balance1) public view returns (uint) {
  //   if (stableSwap) {
  //     uint _x = balance0 * 1e18 / precisionMultiplier0;
  //     uint _y = balance1 * 1e18 / precisionMultiplier1;
  //     uint _a = _x * _y / 1e18;
  //     uint _b = _x * _x / 1e18 + _y * _y / 1e18;
  //     return  _a * _b / 1e18; 
  //   }else{
  //     return balance0 * balance1;
  //   }
  // }

  function _get_y(uint in_and_pool_x, uint pool_xy, uint pool_y) public view returns (uint) {
    for (uint i = 0; i < 255; i++) {
      uint y_prev = pool_y;
      uint in_and_pool_k = _f(in_and_pool_x, pool_y);
      if (in_and_pool_k < pool_xy) {
        uint dy = pool_xy - in_and_pool_k / _d(in_and_pool_x, pool_y);
        pool_y = pool_y + dy;
      } else {
        uint dy = in_and_pool_k - pool_xy / _d(in_and_pool_x, pool_y);
        pool_y = pool_y - dy;
      }
      if (pool_y > y_prev) {
        if (pool_y - y_prev <= 1) {
          return pool_y;
        }
      } else {
        if (y_prev - pool_y <= 1) {
          return pool_y;
        }
      }
    }
    return pool_y;
  }

  function _f(uint x0, uint y) public view returns (uint _f_result) {
    uint _x = x0 / precisionMultiplier0 * 1e18 ;
    uint _y = y / precisionMultiplier1 * 1e18 ;
    uint _r1 = 1e18 / precisionMultiplier0;
    uint _r2 = 1e18 / precisionMultiplier1;
    _f_result = _x * _y / (_r1*_r2) * _y /_r2 * _y /_r2 + _x * _x / (_r1*_r1) * _x * _y /(_r1*_r2) + 1618 * _x / 1000 * _x /(_r1*_r1) * _y * _y /(_r1*_r2);
  }

  function _d(uint x0, uint y) public view returns (uint _d_result) {
    uint _x = x0 / precisionMultiplier0 * 1e18;
    uint _y = y / precisionMultiplier1 * 1e18;
    uint _r1 = 1e18 / precisionMultiplier0;
    uint _r2 = 1e18 / precisionMultiplier1;
    _d_result = _x * _y /(_r1*_r2) * _y /_r2+ _x * _x / (_r1*_r1) * _x /_r1+ 1618 * _x / 1000 * _x / (_r1*_r1) * _y /_r2;
  }

  function getAmountOut(uint amountIn, address tokenIn) external view returns (uint) {
    uint16 feePercent = tokenIn == token0 ? token0FeePercent : token1FeePercent;
    return _getAmountOut(amountIn, tokenIn, uint(reserve0), uint(reserve1), feePercent);
  }

  function _getAmountOut(uint amountIn, address tokenIn, uint _reserve0, uint _reserve1, uint feePercent) internal view returns (uint) {
    if (stableSwap) {
      amountIn = amountIn-amountIn * feePercent / FEE_DENOMINATOR; // remove fee from amount received
      uint xy = _k(_reserve0, _reserve1);
      _reserve0 = _reserve0 * precisionMultiplier0 * 1e18 / precisionMultiplier0;
      _reserve1 = _reserve1 * precisionMultiplier1 * 1e18 / precisionMultiplier1;

      (uint reserveA, uint reserveB) = tokenIn == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
      amountIn = tokenIn == token0 ? amountIn * 1e18 / precisionMultiplier0 : amountIn * 1e18 / precisionMultiplier1;
      uint y = reserveB - _get_y(amountIn + reserveA, xy, reserveB);
      return y * (tokenIn == token0 ? precisionMultiplier1 : precisionMultiplier0) / 1e18;

    } else {
      (uint reserveA, uint reserveB) = tokenIn == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
      amountIn = amountIn*(FEE_DENOMINATOR-feePercent);
      return (amountIn*reserveB) / (reserveA*FEE_DENOMINATOR+amountIn);
    }
  }

  // force balances to match reserves
  function skim(address to) external lock {
    address _token0 = token0;
    // gas savings
    address _token1 = token1;
    // gas savings
    _safeTransfer(_token0, to, getBalance(_token0,address(this))-(reserve0));
    _safeTransfer(_token1, to, getBalance(_token1,address(this))-(reserve1));
  }

  // force reserves to match balances
  function sync() external lock {
    uint token0Balance = getBalance(token0,address(this));
    uint token1Balance = getBalance(token1,address(this));
    require(token0Balance != 0 && token1Balance != 0, "HyperStable: liquidity ratio not initialized");
    _update(token0Balance, token1Balance);
  }

}
