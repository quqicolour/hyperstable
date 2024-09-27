// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0<0.8.20;

interface IHyperStableFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    function pairCodeHash() external view returns (bytes32);

    function getOwner() external view returns (address);
    function getStableOwner() external view returns (address);
    function feeInfo() external view returns (address _feeTo);

    function getThisPair(address tokenA, address tokenB) external view returns (address _pair);
    function indexPair(uint256 index) external view returns (address _indexPair);
    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
}