// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;

import '../libraries/TransferHelper.sol';

import '../interfaces/IHyperStableFactory.sol';
import '../interfaces/IHyperStablePair.sol';
import '../interfaces/IHyperStableERC20.sol';
import '../interfaces/IERC20.sol';

import '../interfaces/IHyperStableRouter.sol';
import '../libraries/HyperStableLibrary.sol';
import '../interfaces/IWETH.sol';

contract HyperStableRouter is IHyperStableRouter {
  address public factory;
  address public WETH;

  modifier ensure(uint deadline) {
    require(deadline >= block.timestamp, 'TenkRouter: EXPIRED');
    _;
  }

  constructor(address _factory, address _WETH){
    factory = _factory;
    WETH = _WETH;
  }

  receive() external payable {
    require(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
  }

  function getPair(address token1, address token2) external view returns (address){
    return HyperStableLibrary.pairFor(factory, token1, token2, getCodeHash());
  }

  function getCodeHash()internal view returns(bytes32 initCodeHash){
    initCodeHash=IHyperStableFactory(factory).pairCodeHash();
  }

  // **** ADD LIQUIDITY ****
  function _addLiquidity(
    address tokenA,
    address tokenB,
    uint amountADesired,
    uint amountBDesired,
    uint amountAMin,
    uint amountBMin
  ) internal returns (uint amountA, uint amountB) {
    // create the pair if it doesn't exist yet
    if (IHyperStableFactory(factory).getThisPair(tokenA, tokenB) == address(0)) {
      IHyperStableFactory(factory).createPair(tokenA, tokenB);
    }
    (uint reserveA, uint reserveB) = HyperStableLibrary.getReserves(factory, tokenA, tokenB, getCodeHash());
    if (reserveA == 0 && reserveB == 0) {
      (amountA, amountB) = (amountADesired, amountBDesired);
    } else {
      uint amountBOptimal = HyperStableLibrary.quote(amountADesired, reserveA, reserveB);
      if (amountBOptimal <= amountBDesired) {
        require(amountBOptimal >= amountBMin, 'TenkRouter: INSUFFICIENT_B_AMOUNT');
        (amountA, amountB) = (amountADesired, amountBOptimal);
      } else {
        uint amountAOptimal = HyperStableLibrary.quote(amountBDesired, reserveB, reserveA);
        assert(amountAOptimal <= amountADesired);
        require(amountAOptimal >= amountAMin, 'TenkRouter: INSUFFICIENT_A_AMOUNT');
        (amountA, amountB) = (amountAOptimal, amountBDesired);
      }
    }
  }

  function addLiquidity(
    address tokenA,
    address tokenB,
    uint amountADesired,
    uint amountBDesired,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline
  ) external override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
    (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
    address pair = HyperStableLibrary.pairFor(factory, tokenA, tokenB, getCodeHash());
    TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
    TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
    liquidity = IHyperStablePair(pair).mint(to);
  }

  function addLiquidityETH(
    address token,
    uint amountTokenDesired,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline
  ) external override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
    (amountToken, amountETH) = _addLiquidity(
      token,
      WETH,
      amountTokenDesired,
      msg.value,
      amountTokenMin,
      amountETHMin
    );
    address pair = HyperStableLibrary.pairFor(factory, token, WETH, getCodeHash());
    TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
    IWETH(WETH).deposit{value : amountETH}();
    assert(IWETH(WETH).transfer(pair, amountETH));
    liquidity = IHyperStablePair(pair).mint(to);
    // refund dust eth, if any
    if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
  }

  // **** REMOVE LIQUIDITY ****
  function removeLiquidity(
    address tokenA,
    address tokenB,
    uint liquidity,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline
  ) public override ensure(deadline) returns (uint amountA, uint amountB) {
    address pair = HyperStableLibrary.pairFor(factory, tokenA, tokenB, getCodeHash());
    IHyperStableERC20(pair).transferFrom(msg.sender, pair, liquidity);
    // send liquidity to pair
    (uint amount0, uint amount1) = IHyperStablePair(pair).burn(to);
    (address token0,) = HyperStableLibrary.sortTokens(tokenA, tokenB);
    (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
    require(amountA >= amountAMin, 'TenkRouter: INSUFFICIENT_A_AMOUNT');
    require(amountB >= amountBMin, 'TenkRouter: INSUFFICIENT_B_AMOUNT');
  }

  function removeLiquidityETH(
    address token,
    uint liquidity,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline
  ) public override ensure(deadline) returns (uint amountToken, uint amountETH) {
    (amountToken, amountETH) = removeLiquidity(
      token,
      WETH,
      liquidity,
      amountTokenMin,
      amountETHMin,
      address(this),
      deadline
    );
    TransferHelper.safeTransfer(token, to, amountToken);
    IWETH(WETH).withdraw(amountETH);
    TransferHelper.safeTransferETH(to, amountETH);
  }

  function removeLiquidityWithPermit(
    address tokenA,
    address tokenB,
    uint liquidity,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline,
    bool approveMax, uint8 v, bytes32 r, bytes32 s
  ) external override returns (uint amountA, uint amountB) {
    address pair = HyperStableLibrary.pairFor(factory, tokenA, tokenB, getCodeHash());
    uint value = approveMax ? type(uint256).max : liquidity;
    IHyperStableERC20(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
    (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
  }

  function removeLiquidityETHWithPermit(
    address token,
    uint liquidity,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline,
    bool approveMax, uint8 v, bytes32 r, bytes32 s
  ) external override returns (uint amountToken, uint amountETH) {
    address pair = HyperStableLibrary.pairFor(factory, token, WETH, getCodeHash());
    uint value = approveMax ? type(uint256).max : liquidity;
    IHyperStableERC20(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
    (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
  }

  // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
  function removeLiquidityETHSupportingFeeOnTransferTokens(
    address token,
    uint liquidity,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline
  ) public override ensure(deadline) returns (uint amountETH) {
    (, amountETH) = removeLiquidity(
      token,
      WETH,
      liquidity,
      amountTokenMin,
      amountETHMin,
      address(this),
      deadline
    );
    TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
    IWETH(WETH).withdraw(amountETH);
    TransferHelper.safeTransferETH(to, amountETH);
  }

  function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
    address token,
    uint liquidity,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline,
    bool approveMax, uint8 v, bytes32 r, bytes32 s
  ) external override returns (uint amountETH) {
    address pair = HyperStableLibrary.pairFor(factory, token, WETH, getCodeHash());
    uint value = approveMax ? type(uint256).max : liquidity;
    IHyperStableERC20(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
    amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
      token, liquidity, amountTokenMin, amountETHMin, to, deadline
    );
  }

  // **** SWAP ****

  // **** SWAP (supporting fee-on-transfer tokens) ****
  // requires the initial amount to have already been sent to the first pair
  function _swap(uint[] memory amounts, address[] memory path, address _to) internal {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = HyperStableLibrary.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? HyperStableLibrary.pairFor(factory, output, path[i + 2], getCodeHash()) : _to;
            IHyperStablePair(HyperStableLibrary.pairFor(factory, input, output, getCodeHash())).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
  }

  function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        amounts = HyperStableLibrary.getAmountsOut(factory, amountIn, path, getCodeHash());
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, HyperStableLibrary.pairFor(factory, path[0], path[1], getCodeHash()), amounts[0]
        );
        _swap(amounts, path, to);
  }

  function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal {
    for (uint i; i < path.length - 1; i++) {
      (address input, address output) = (path[i], path[i + 1]);
      (address token0,) = HyperStableLibrary.sortTokens(input, output);
      IHyperStablePair pair = IHyperStablePair(HyperStableLibrary.pairFor(factory, input, output, getCodeHash()));
      uint amountOutput;
      {// scope to avoid stack too deep errors
        (uint reserve0, uint reserve1,,) = pair.getReserves();
        // permute values to force reserve0 == inputReserve
        if (input != token0) (reserve0, reserve1) = (reserve1, reserve0);
        uint amountInput = IERC20(input).balanceOf(address(pair))-reserve0;
        amountOutput = pair.getAmountOut(amountInput, input);
      }

      (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
      address to = i < path.length - 2 ? HyperStableLibrary.pairFor(factory, output, path[i + 2], getCodeHash()) : _to;
      pair.swap(amount0Out, amount1Out, to, new bytes(0));
    }
  }

  function swapExactTokensForTokensSupportingFeeOnTransferTokens(
    uint amountIn,
    uint amountOutMin,
    address[] calldata path,
    address to,
    uint deadline
  ) external override ensure(deadline) {
    TransferHelper.safeTransferFrom(
      path[0], msg.sender, HyperStableLibrary.pairFor(factory, path[0], path[1], getCodeHash()), amountIn
    );
    uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
    _swapSupportingFeeOnTransferTokens(path, to);
    require(
      IERC20(path[path.length - 1]).balanceOf(to)-balanceBefore >= amountOutMin,
      'TenkRouter: INSUFFICIENT_OUTPUT_AMOUNT'
    );
  }

  function swapExactETHForTokensSupportingFeeOnTransferTokens(
    uint amountOutMin,
    address[] calldata path,
    address to,
    uint deadline
  )
  external
  override
  payable
  ensure(deadline)
  {
    require(path[0] == WETH, 'TenkRouter: INVALID_PATH');
    uint amountIn = msg.value;
    IWETH(WETH).deposit{value : amountIn}();
    assert(IWETH(WETH).transfer(HyperStableLibrary.pairFor(factory, path[0], path[1], getCodeHash()), amountIn));

    uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
    _swapSupportingFeeOnTransferTokens(path, to);
    require(
      IERC20(path[path.length - 1]).balanceOf(to)-balanceBefore >= amountOutMin,
      'TenkRouter: INSUFFICIENT_OUTPUT_AMOUNT'
    );
  }

  function swapExactTokensForETHSupportingFeeOnTransferTokens(
    uint amountIn,
    uint amountOutMin,
    address[] calldata path,
    address to,
    uint deadline
  )
  external
  override
  ensure(deadline)
  {
    require(path[path.length - 1] == WETH, 'TenkRouter: INVALID_PATH');
    TransferHelper.safeTransferFrom(
      path[0], msg.sender, HyperStableLibrary.pairFor(factory, path[0], path[1], getCodeHash()), amountIn
    );
    _swapSupportingFeeOnTransferTokens(path, address(this));
    uint amountOut = IERC20(WETH).balanceOf(address(this));
    require(amountOut >= amountOutMin, 'TenkRouter: INSUFFICIENT_OUTPUT_AMOUNT');
    IWETH(WETH).withdraw(amountOut);
    TransferHelper.safeTransferETH(to, amountOut);
  }


  // **** LIBRARY FUNCTIONS ****
  // given some amount of an asset and pair reserves, returns the quote of the other asset's reserve ratio
  function quote(uint amountA, uint reserveA, uint reserveB) external pure override returns (uint amountB) {
    return HyperStableLibrary.quote(amountA, reserveA, reserveB);
  }

  function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts) {
    return HyperStableLibrary.getAmountsOut(factory, amountIn, path, getCodeHash());
  }
}