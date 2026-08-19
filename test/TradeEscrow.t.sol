// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "../contracts/MockWAVAX.sol";
import "../contracts/MockUSDC.sol";
import "../contracts/TradeEscrow.sol";

contract TradeEscrowTest is Test {
    MockWAVAX public wavax;
    MockUSDC public usdc;
    TradeEscrow public escrow;

    address public executor = makeAddr("executor");
    address public settlementMessenger = makeAddr("settlementMessenger");
    address public initiatorPayout = makeAddr("initiatorPayout");
    address public keeper = makeAddr("keeper");
    address public unauthorized = makeAddr("unauthorized");

    uint256 public constant COMMISSION_BPS = 5;
    uint256 public constant AMOUNT_IN = 500_000e18; // 500,000 MockWAVAX
    uint256 public constant MIN_AMOUNT_OUT = 1_000e6; // 1,000 MockUSDC
    bytes32 public constant ORDER_ID = keccak256("order-1");

    function setUp() public {
        wavax = new MockWAVAX();
        usdc = new MockUSDC();
        escrow = new TradeEscrow(executor, settlementMessenger, COMMISSION_BPS);

        wavax.mint(executor, AMOUNT_IN);
        vm.prank(executor);
        wavax.approve(address(escrow), AMOUNT_IN);
    }

    function _getTrade(bytes32 orderId) internal view returns (TradeEscrow.Trade memory) {
        (
            address tokenIn,
            address tokenOut,
            address payout,
            uint256 amountIn,
            uint256 minAmountOut,
            uint256 commissionAmount,
            bool funded,
            bool executed,
            bool commissionPaid
        ) = escrow.trades(orderId);
        return TradeEscrow.Trade(
            tokenIn, tokenOut, payout, amountIn, minAmountOut, commissionAmount, funded, executed, commissionPaid
        );
    }

    function _openLeg(bytes32 orderId) internal {
        vm.prank(settlementMessenger);
        escrow.openLeg(orderId, address(wavax), address(usdc), AMOUNT_IN, MIN_AMOUNT_OUT, initiatorPayout);
    }

    function _depositOutput(bytes32, uint256 amount) internal {
        usdc.mint(executor, amount);
        vm.startPrank(executor);
        usdc.transfer(address(escrow), amount);
        vm.stopPrank();
    }

    function _closeLeg(bytes32 orderId) internal {
        vm.prank(executor);
        escrow.closeOpenLeg(orderId);
    }

    function testOpenLegHappyPath() public {
        uint256 expectedCommission = (AMOUNT_IN * COMMISSION_BPS) / 10_000; // 250e18
        uint256 expectedTradeAmount = AMOUNT_IN - expectedCommission;

        _openLeg(ORDER_ID);

        TradeEscrow.Trade memory trade = _getTrade(ORDER_ID);
        assertTrue(trade.funded);
        assertFalse(trade.executed);
        assertFalse(trade.commissionPaid);
        assertEq(trade.tokenIn, address(wavax));
        assertEq(trade.tokenOut, address(usdc));
        assertEq(trade.initiatorPayout, initiatorPayout);
        assertEq(trade.amountIn, AMOUNT_IN);
        assertEq(trade.minAmountOut, MIN_AMOUNT_OUT);
        assertEq(trade.commissionAmount, expectedCommission);

        // Escrow holds only commission; executor received the tradeable remainder.
        assertEq(wavax.balanceOf(address(escrow)), expectedCommission);
        assertEq(wavax.balanceOf(executor), expectedTradeAmount);
    }

    function testOpenLegByExecutor() public {
        vm.prank(executor);
        escrow.openLeg(ORDER_ID, address(wavax), address(usdc), AMOUNT_IN, MIN_AMOUNT_OUT, initiatorPayout);
        assertTrue(_getTrade(ORDER_ID).funded);
    }

    function testOpenLegUnauthorizedReverts() public {
        vm.prank(unauthorized);
        vm.expectRevert(TradeEscrow.Unauthorized.selector);
        escrow.openLeg(ORDER_ID, address(wavax), address(usdc), AMOUNT_IN, MIN_AMOUNT_OUT, initiatorPayout);
    }

    function testDuplicateOrderReverts() public {
        _openLeg(ORDER_ID);
        vm.prank(settlementMessenger);
        vm.expectRevert(TradeEscrow.DuplicateOrder.selector);
        escrow.openLeg(ORDER_ID, address(wavax), address(usdc), AMOUNT_IN, MIN_AMOUNT_OUT, initiatorPayout);
    }

    function testCommissionFloorRounding() public {
        uint256 smallAmount = 100;
        wavax.mint(executor, smallAmount);
        vm.prank(executor);
        wavax.approve(address(escrow), smallAmount);

        uint256 agentBalanceBefore = wavax.balanceOf(executor);

        vm.prank(settlementMessenger);
        escrow.openLeg(ORDER_ID, address(wavax), address(usdc), smallAmount, 1, initiatorPayout);

        TradeEscrow.Trade memory trade = _getTrade(ORDER_ID);
        assertEq(trade.commissionAmount, 0); // floor(100 * 5 / 10000) = 0
        assertEq(wavax.balanceOf(address(escrow)), 0);
        assertEq(wavax.balanceOf(executor), agentBalanceBefore);
    }

    function testCloseOpenLegHappyPath() public {
        _openLeg(ORDER_ID);
        _depositOutput(ORDER_ID, MIN_AMOUNT_OUT);

        uint256 agentOutputBefore = usdc.balanceOf(executor);

        vm.expectEmit(true, true, true, true);
        emit TradeEscrow.TradeExecuted(ORDER_ID, MIN_AMOUNT_OUT);

        _closeLeg(ORDER_ID);

        TradeEscrow.Trade memory trade = _getTrade(ORDER_ID);
        assertTrue(trade.executed);
        assertEq(usdc.balanceOf(address(escrow)), 0);
        assertEq(usdc.balanceOf(executor), agentOutputBefore + MIN_AMOUNT_OUT);
    }

    function testCloseBeforeFundingReverts() public {
        vm.prank(executor);
        vm.expectRevert(TradeEscrow.NotFunded.selector);
        escrow.closeOpenLeg(ORDER_ID);
    }

    function testCloseTwiceReverts() public {
        _openLeg(ORDER_ID);
        _depositOutput(ORDER_ID, MIN_AMOUNT_OUT);
        _closeLeg(ORDER_ID);

        vm.prank(executor);
        vm.expectRevert(TradeEscrow.AlreadyExecuted.selector);
        escrow.closeOpenLeg(ORDER_ID);
    }

    function testBelowMinOutputReverts() public {
        _openLeg(ORDER_ID);
        _depositOutput(ORDER_ID, MIN_AMOUNT_OUT - 1);

        vm.prank(executor);
        vm.expectRevert(TradeEscrow.SlippageFailed.selector);
        escrow.closeOpenLeg(ORDER_ID);
    }

    function testPayCommissionBeforeExecutionReverts() public {
        _openLeg(ORDER_ID);
        vm.prank(keeper);
        vm.expectRevert(TradeEscrow.NotExecuted.selector);
        escrow.payOpenCommission(ORDER_ID);
    }

    function testPayCommissionHappyPath() public {
        _openLeg(ORDER_ID);
        _depositOutput(ORDER_ID, MIN_AMOUNT_OUT);
        _closeLeg(ORDER_ID);

        uint256 expectedCommission = (AMOUNT_IN * COMMISSION_BPS) / 10_000;

        vm.prank(keeper);
        escrow.payOpenCommission(ORDER_ID);

        TradeEscrow.Trade memory trade = _getTrade(ORDER_ID);
        assertTrue(trade.commissionPaid);
        assertEq(wavax.balanceOf(initiatorPayout), expectedCommission);
        assertEq(wavax.balanceOf(address(escrow)), 0);
        assertEq(wavax.balanceOf(keeper), 0);
    }

    function testPayCommissionTwiceReverts() public {
        _openLeg(ORDER_ID);
        _depositOutput(ORDER_ID, MIN_AMOUNT_OUT);
        _closeLeg(ORDER_ID);

        vm.prank(keeper);
        escrow.payOpenCommission(ORDER_ID);

        vm.prank(keeper);
        vm.expectRevert(TradeEscrow.AlreadyPaid.selector);
        escrow.payOpenCommission(ORDER_ID);
    }

    function testPayoutCannotBeRedirectedByCaller() public {
        _openLeg(ORDER_ID);
        _depositOutput(ORDER_ID, MIN_AMOUNT_OUT);
        _closeLeg(ORDER_ID);

        uint256 expectedCommission = (AMOUNT_IN * COMMISSION_BPS) / 10_000;

        vm.prank(unauthorized);
        escrow.payOpenCommission(ORDER_ID);

        assertEq(wavax.balanceOf(initiatorPayout), expectedCommission);
        assertEq(wavax.balanceOf(unauthorized), 0);
    }

    function testNoResidualOutputAfterClose() public {
        _openLeg(ORDER_ID);
        _depositOutput(ORDER_ID, MIN_AMOUNT_OUT);
        _closeLeg(ORDER_ID);
        assertEq(usdc.balanceOf(address(escrow)), 0);
    }

    function testNoResidualInputAfterPayout() public {
        _openLeg(ORDER_ID);
        _depositOutput(ORDER_ID, MIN_AMOUNT_OUT);
        _closeLeg(ORDER_ID);
        vm.prank(keeper);
        escrow.payOpenCommission(ORDER_ID);
        assertEq(wavax.balanceOf(address(escrow)), 0);
    }
}
