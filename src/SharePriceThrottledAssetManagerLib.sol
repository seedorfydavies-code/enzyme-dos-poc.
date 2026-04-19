// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;
import "./Mocks.sol";

contract SharePriceThrottledAssetManagerLib {
    event Initialized(address indexed vaultProxy, uint64 lossTolerance, uint32 lossTolerancePeriodDuration, address indexed shutDowner);
    event ThrottleUpdated(uint256 nextCumulativeLoss);
    event OwnerSet(address nextOwner);

    error AlreadyInitialized();
    error ExceedsOneHundredPercent();
    error ToleranceExceeded(uint256 cumulativeLoss);
    error Unauthorized();

    uint256 private constant ONE_HUNDRED_PERCENT = 1e18;
    address private owner;
    address private shutdowner;
    address private vaultProxyAddress;
    uint64  private lossTolerance;
    uint32  private lossTolerancePeriodDuration;
    struct Throttle { uint64 cumulativeLoss; uint64 lastLossTimestamp; }
    Throttle private throttle;
    MockFundValueCalculator private immutable FUND_VALUE_CALCULATOR;

    constructor(MockFundValueCalculator _calc) { FUND_VALUE_CALCULATOR = _calc; }

    function init(address _owner, address _vaultProxyAddress, uint64 _lossTolerance, uint32 _lossTolerancePeriodDuration, address _shutdowner) external {
        if (vaultProxyAddress != address(0)) revert AlreadyInitialized();
        if (_lossTolerance > ONE_HUNDRED_PERCENT) revert ExceedsOneHundredPercent();
        owner = _owner;
        vaultProxyAddress = _vaultProxyAddress;
        lossTolerance = _lossTolerance;
        lossTolerancePeriodDuration = _lossTolerancePeriodDuration;
        shutdowner = _shutdowner;
        emit Initialized(_vaultProxyAddress, _lossTolerance, _lossTolerancePeriodDuration, _shutdowner);
        emit OwnerSet(_owner);
    }

    struct Call { address target; bytes data; }

    function executeCalls(Call[] calldata _calls) external {
        if (msg.sender != owner) revert Unauthorized();
        uint256 prevSharePrice = __getSharePrice();
        for (uint256 i; i < _calls.length; i++) {
            (bool ok,) = _calls[i].target.call(_calls[i].data);
            require(ok, "Call failed");
        }
        __validateAndUpdateThrottle(prevSharePrice);
    }

    function __validateAndUpdateThrottle(uint256 _prevSharePrice) private {
        uint256 currentSharePrice = __getSharePrice();
        if (currentSharePrice >= _prevSharePrice) return;
        uint256 nextCumulativeLoss = throttle.cumulativeLoss;
        if (nextCumulativeLoss > 0) {
            uint256 cumulativeLossToRestore = uint256(lossTolerance) * (block.timestamp - throttle.lastLossTimestamp) / lossTolerancePeriodDuration;
            if (cumulativeLossToRestore < nextCumulativeLoss) { nextCumulativeLoss -= cumulativeLossToRestore; }
            else { nextCumulativeLoss = 0; }
        }
        uint256 newLoss = ONE_HUNDRED_PERCENT * (_prevSharePrice - currentSharePrice) / _prevSharePrice;
        nextCumulativeLoss += newLoss;
        if (nextCumulativeLoss > lossTolerance) { revert ToleranceExceeded(nextCumulativeLoss); }
        throttle.cumulativeLoss = uint64(nextCumulativeLoss);
        throttle.lastLossTimestamp = uint64(block.timestamp);
        emit ThrottleUpdated(nextCumulativeLoss);
    }

    function __getSharePrice() private returns (uint256 price_) {
        (, price_) = FUND_VALUE_CALCULATOR.calcGrossShareValue(vaultProxyAddress);
    }

    function getOwner() external view returns (address) { return owner; }
    function getVaultProxyAddress() external view returns (address) { return vaultProxyAddress; }
    function getLossTolerancePeriodDuration() external view returns (uint32) { return lossTolerancePeriodDuration; }
    function getThrottle() external view returns (Throttle memory) { return throttle; }
}
