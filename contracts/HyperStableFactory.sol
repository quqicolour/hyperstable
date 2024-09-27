// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;

import '../interfaces/IHyperStableFactory.sol';
import './HyperStablePair.sol';

contract HyperStableFactory is IHyperStableFactory{
    address private owner;
    address private stableOwner;
    address private feeTo;

    address[] private allPairs;

    mapping(address => mapping(address => address)) private getPair;
    
    // event PairCreated(address indexed token0, address indexed token1, address pair, uint length);
    // event FeeToTransferred(address indexed prevFeeTo, address indexed newFeeTo);
    // event OwnershipTransferred(address indexed prevOwner, address indexed newOwner);
    // event SetStableOwnershipTransferred(address indexed prevOwner, address indexed newOwner);

    constructor(address feeTo_){
        owner = msg.sender;
        stableOwner = msg.sender;
        feeTo = feeTo_;

        // emit OwnershipTransferred(address(0), msg.sender);
        // emit SetStableOwnershipTransferred(address(0), msg.sender);
        // emit FeeToTransferred(address(0), feeTo_);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner == msg.sender, "Non owner");
        _;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function pairCodeHash() external view returns (bytes32) {
        return keccak256(type(HyperStablePair).creationCode);
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'TenkStableFactory: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'TenkStableFactory: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'TenkStableFactory: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(HyperStablePair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        require(pair != address(0));
        HyperStablePair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setOwner(address _owner) external onlyOwner {
        require(_owner != address(0));
        // emit OwnershipTransferred(owner, _owner);
        owner = _owner;
    }

    function setStableOwner(address _setStableOwner) external {
        require(msg.sender == stableOwner);
        require(_setStableOwner != address(0));
        // emit SetStableOwnershipTransferred(setStableOwner, _setStableOwner);
        stableOwner = _setStableOwner;
    }

    function setFeeTo(address _feeTo) external onlyOwner {
        // emit FeeToTransferred(feeTo, _feeTo);
        feeTo = _feeTo;
    }

    function feeInfo() external view returns (address _feeTo) {
        _feeTo = feeTo;
    }

    function getOwner()external view returns (address _owner){
        _owner=owner;
    }

    function getStableOwner()external view returns (address _StableOwner){
        _StableOwner=stableOwner;
    }

    function getThisPair(address tokenA, address tokenB)external view returns(address _pair){
        _pair = getPair[tokenA][tokenB];
    }

    function indexPair(uint256 index)external view returns(address _indexPair){
        _indexPair=allPairs[index];
    }

}