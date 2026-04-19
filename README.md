# Enzyme Blue — DoS PoC
## `SharePriceThrottledAssetManagerLib`: Missing Validation for `_lossTolerancePeriodDuration`

**Researcher:** CONDEZ  
**Severity:** Medium  
**Program:** [Enzyme Blue on Immunefi](https://immunefi.com/bug-bounty/enzymefinance/scope/)  
**Contract:** [`0x7A5125491025cF44380b6D95EC385ddd37455C22`](https://basescan.org/address/0x7A5125491025cF44380b6D95EC385ddd37455C22) (Base Mainnet)  
**Impact:** Smart contract unable to operate — `executeCalls()` permanently frozen

---

## Bug Description

`SharePriceThrottledAssetManagerLib.init()` validates that `_lossTolerance` does not exceed 100%, but **does not validate that `_lossTolerancePeriodDuration` is greater than zero**.

If the contract is initialized with `_lossTolerancePeriodDuration = 0`, the second call to `executeCalls()` that causes a loss in the vault's share price reverts with **`panic: division or modulo by zero (0x12)`**, permanently locking the asset manager.

### Vulnerable Code

```solidity
// SharePriceThrottledAssetManagerLib.sol — init() function

function init(
    address _owner,
    address _vaultProxyAddress,
    uint64  _lossTolerance,
    uint32  _lossTolerancePeriodDuration,   // <-- can be 0
    address _shutdowner
) external override {
    if (getVaultProxyAddress() != address(0)) revert AlreadyInitialized();
    if (_lossTolerance > ONE_HUNDRED_PERCENT) revert ExceedsOneHundredPercent();

    // MISSING: if (_lossTolerancePeriodDuration == 0) revert InvalidDuration();

    // ... rest of init
}
```

### Where the Panic Occurs

```solidity
// __validateAndUpdateThrottle() — called internally from executeCalls()

if (nextCumulativeLoss > 0) {
    uint256 cumulativeLossToRestore =
        uint256(lossTolerance)
        * (block.timestamp - throttle.lastLossTimestamp)
        / lossTolerancePeriodDuration;   // <-- PANIC 0x12 when it is 0
}
```

---

## Exploit Flow

```
1. Manager calls init(_owner, _vault, lossTolerance, 0, _shutdowner)
   └── Does not revert — duration=0 is accepted without validation

2. Manager calls executeCalls([...]) — first operation with a loss
   └── cumulativeLoss was 0, no division -> OK
   └── cumulativeLoss is stored in storage

3. Manager calls executeCalls([...]) — second operation with a loss
   └── cumulativeLoss > 0, attempts to calculate replenishment
   └── division by lossTolerancePeriodDuration=0
   └── PANIC: division or modulo by zero (0x12)
   └── executeCalls() is PERMANENTLY LOCKED
```

---

## Reproducing the PoC

### Requirements

- [Foundry](https://getfoundry.sh/) installed
- Git

### Steps

```bash
# 1. Clone the repository
git clone https://github.com/YOUR_USERNAME/enzyme-dos-poc
cd enzyme-dos-poc

# 2. Install dependencies
forge install foundry-rs/forge-std --no-git

# 3. Run the tests
forge test --match-contract EnzymeThrottleDoSPoC -vvvv
```

### Expected Output

```
Ran 3 tests for test/EnzymePoC.t.sol:EnzymeThrottleDoSPoC

[PASS] test_1_Init_AcceptsDurationZero_NoValidation() (gas: ~35000)
Logs:
  init() completed WITHOUT reverting
  lossTolerancePeriodDuration: 0
  [BUG] Missing: require(_lossTolerancePeriodDuration > 0)

[PASS] test_2_FullCallPath_PermanentDoS() (gas: ~70000)
Logs:
  [1] init(duration=0): OK - did not revert
  [2] executeCalls() 10% loss: OK
      cumulativeLoss: 100000000000000000
  [3] executeCalls() second loss (cumulativeLoss > 0)...
      [CONFIRMED] panic: division or modulo by zero (0x12)
      [IMPACT]    executeCalls() PERMANENTLY LOCKED

[PASS] test_3_ValidDuration_NoDoS_Contrast() (gas: ~75000)
Logs:
  First executeCalls() 1% loss: OK
  Second executeCalls() 1% loss: OK
  [CONTRAST] With duration=86400 the contract works correctly

Suite result: ok. 3 passed; 0 failed
```

### Panic Trace (test 2)

```
VulnerableThrottleLogic::validateAndUpdateThrottle(9e17, 8e17)
    └─ ← [Revert] panic: division or modulo by zero (0x12)
```

The panic code `0x12` in Solidity corresponds specifically to **division or modulo by zero**. This is irrefutable.

---

## Recommended Fix

Add a validation in `init()`:

```solidity
function init(
    address _owner,
    address _vaultProxyAddress,
    uint64  _lossTolerance,
    uint32  _lossTolerancePeriodDuration,
    address _shutdowner
) external override {
    if (getVaultProxyAddress() != address(0)) revert AlreadyInitialized();
    if (_lossTolerance > ONE_HUNDRED_PERCENT)  revert ExceedsOneHundredPercent();
    if (_lossTolerancePeriodDuration == 0)     revert InvalidDuration();  // ADD THIS

    // ... rest of init unchanged
}
```

---

## Repository Structure

```
enzyme-dos-poc/
├── src/
│   ├── SharePriceThrottledAssetManagerLib.sol  <- replica of the vulnerable contract
│   └── Mocks.sol                               <- FundValueCalculator and helpers
├── test/
│   └── EnzymePoC.t.sol                         <- 3 PoC tests
├── foundry.toml
└── README.md
```

---

## Immunefi Classification

| Field | Value |
|---|---|
| Severity | Medium |
| Impact | Smart contract unable to operate |
| Attack vector | Misconfiguration accepted by contract |
| Affected users | Asset manager initialized with duration=0 |
| Funds at risk | Indirect — operations blocked, no direct theft |

---

*Reported by: **CONDEZ***
