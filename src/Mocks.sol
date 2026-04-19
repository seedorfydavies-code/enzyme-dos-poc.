// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

contract MockFundValueCalculator {
    uint256 public price;
    constructor(uint256 _initialPrice) { price = _initialPrice; }
    function setPrice(uint256 _p) external { price = _p; }
    function calcGrossShareValue(address) external view returns (address, uint256) {
        return (address(0), price);
    }
}

contract MockAddressListRegistry {
    function isInList(uint256, address) external pure returns (bool) { return false; }
}

contract PriceManipulator {
    MockFundValueCalculator public calc;
    uint256 public targetPrice;
    constructor(MockFundValueCalculator _calc, uint256 _targetPrice) {
        calc = _calc;
        targetPrice = _targetPrice;
    }
    function execute() external { calc.setPrice(targetPrice); }
}
