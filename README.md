# Enzyme Blue — DoS PoC
## Missing Validation for lossTolerancePeriodDuration
**Researcher:** CONDEZ
**Impact:** Permanent DoS in executeCalls()
### Description
If duration is 0, the second loss triggers a division-by-zero panic (0x12).
