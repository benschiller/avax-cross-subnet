// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "../contracts/MockWAVAX.sol";
import "../contracts/MockUSDC.sol";
import "../contracts/MockDEX.sol";
import "../contracts/TradeEscrow.sol";
import "../contracts/InitiatorMessenger.sol";
import "../contracts/SettlementMessenger.sol";
import "@teleporter/teleporter/ITeleporterMessenger.sol";
import "./mocks/MockTeleporterMessenger.sol";

contract CrossSubnetFlowTest is Test {
    MockWAVAX public wavax;
    MockUSDC public usdc;
    MockDEX public dex;
    TradeEscrow public escrow;
    InitiatorMessenger public initiatorMessenger;
    SettlementMessenger public settlementMessenger;

    address public initiator = makeAddr("initiator");
    address public executor = makeAddr("executor");
    address public initiatorPayout = makeAddr("initiatorPayout");
    address public keeper = makeAddr("keeper");
    address public deployer = makeAddr("deployer");

    bytes32 public initiatorBlockchainID = keccak256("initiator-chain");
    bytes32 public settlementBlockchainID = keccak256("settlement-chain");

    uint256 public constant COMMISSION_BPS = 5;
    uint256 public constant AMOUNT_IN = 500_000e18;
    uint256 public constant MIN_AMOUNT_OUT = 1_000e6;
    bytes32 public constant ORDER_ID = keccak256("cross-subnet-order");

    // The Teleporter messenger is simulated by this contract in tests.
    MockTeleporterMessenger public teleporter;

    function setUp() public {
        vm.startPrank(deployer);

        wavax = new MockWAVAX();
        usdc = new MockUSDC();
        dex = new MockDEX();
        teleporter = new MockTeleporterMessenger();

        // Deploy SettlementMessenger with a placeholder initiator messenger address.
        settlementMessenger = new SettlementMessenger(address(teleporter), initiatorBlockchainID, address(0));
        escrow = new TradeEscrow(executor, address(settlementMessenger), COMMISSION_BPS);
        settlementMessenger.setEscrow(address(escrow));

        // Deploy InitiatorMessenger now that SettlementMessenger is known.
        initiatorMessenger = new InitiatorMessenger(
            address(teleporter), settlementBlockchainID, address(settlementMessenger), initiatorPayout
        );

        // Finalize the trusted initiator messenger address.
        settlementMessenger.setInitiatorMessenger(address(initiatorMessenger));

        vm.stopPrank();

        // Fund the DEX with output liquidity.
        usdc.mint(address(dex), 1_000_000e6);

        // Fund and approve the executor.
        wavax.mint(executor, AMOUNT_IN);
        vm.prank(executor);
        wavax.approve(address(escrow), AMOUNT_IN);
    }

    function testInitiatorMessengerSendOrder() public {
        vm.prank(initiator);
        bytes32 messageID = initiatorMessenger.sendOrder(
            ORDER_ID, address(wavax), address(usdc), AMOUNT_IN, MIN_AMOUNT_OUT, COMMISSION_BPS, initiatorPayout
        );
        assertTrue(messageID != bytes32(0));
    }

    function testSettlementMessengerRejectsNonTeleporter() public {
        bytes memory message = abi.encode(
            uint8(1), ORDER_ID, address(wavax), address(usdc), AMOUNT_IN, MIN_AMOUNT_OUT, COMMISSION_BPS, initiatorPayout
        );

        vm.prank(initiator);
        vm.expectRevert(SettlementMessenger.UnauthorizedTeleporter.selector);
        settlementMessenger.receiveTeleporterMessage(initiatorBlockchainID, address(initiatorMessenger), message);
    }

    function testSettlementMessengerRejectsWrongSourceBlockchain() public {
        bytes memory message = abi.encode(
            uint8(1), ORDER_ID, address(wavax), address(usdc), AMOUNT_IN, MIN_AMOUNT_OUT, COMMISSION_BPS, initiatorPayout
        );

        vm.prank(address(teleporter));
        vm.expectRevert(SettlementMessenger.InvalidSourceBlockchain.selector);
        settlementMessenger.receiveTeleporterMessage(keccak256("wrong-chain"), address(initiatorMessenger), message);
    }

    function testSettlementMessengerRejectsWrongOriginSender() public {
        bytes memory message = abi.encode(
            uint8(1), ORDER_ID, address(wavax), address(usdc), AMOUNT_IN, MIN_AMOUNT_OUT, COMMISSION_BPS, initiatorPayout
        );

        vm.prank(address(teleporter));
        vm.expectRevert(SettlementMessenger.InvalidOriginSender.selector);
        settlementMessenger.receiveTeleporterMessage(initiatorBlockchainID, makeAddr("wrong-sender"), message);
    }

    function testSettlementMessengerRejectsInvalidMessageType() public {
        bytes memory message = abi.encode(
            uint8(99), ORDER_ID, address(wavax), address(usdc), AMOUNT_IN, MIN_AMOUNT_OUT, COMMISSION_BPS, initiatorPayout
        );

        vm.prank(address(teleporter));
        vm.expectRevert(SettlementMessenger.InvalidMessageType.selector);
        settlementMessenger.receiveTeleporterMessage(initiatorBlockchainID, address(initiatorMessenger), message);
    }

    function testEndToEndFlow() public {
        // 1. Initiator sends order.
        vm.prank(initiator);
        initiatorMessenger.sendOrder(
            ORDER_ID, address(wavax), address(usdc), AMOUNT_IN, MIN_AMOUNT_OUT, COMMISSION_BPS, initiatorPayout
        );

        // 2. Teleporter delivers the message to SettlementMessenger.
        bytes memory message = abi.encode(
            uint8(1), ORDER_ID, address(wavax), address(usdc), AMOUNT_IN, MIN_AMOUNT_OUT, COMMISSION_BPS, initiatorPayout
        );
        vm.prank(address(teleporter));
        settlementMessenger.receiveTeleporterMessage(initiatorBlockchainID, address(initiatorMessenger), message);

        // 3. Escrow is funded and trade amount returned.
        (,,, uint256 amountIn,, uint256 commissionAmount, bool funded,,) = escrow.trades(ORDER_ID);
        assertTrue(funded);
        assertEq(amountIn, AMOUNT_IN);
        assertEq(commissionAmount, (AMOUNT_IN * COMMISSION_BPS) / 10_000);
        assertEq(wavax.balanceOf(address(escrow)), commissionAmount);
        assertEq(wavax.balanceOf(executor), AMOUNT_IN - commissionAmount);

        // 4. Executor swaps on MockDEX.
        uint256 tradeAmount = AMOUNT_IN - commissionAmount;
        vm.startPrank(executor);
        wavax.approve(address(dex), tradeAmount);
        dex.swap(address(wavax), address(usdc), tradeAmount, MIN_AMOUNT_OUT, executor);
        usdc.transfer(address(escrow), MIN_AMOUNT_OUT);
        escrow.closeOpenLeg(ORDER_ID);
        vm.stopPrank();

        // 5. Keeper triggers commission payout.
        vm.prank(keeper);
        escrow.payOpenCommission(ORDER_ID);

        // 6. Verify final state.
        assertEq(usdc.balanceOf(address(escrow)), 0);
        assertEq(wavax.balanceOf(address(escrow)), 0);
        assertEq(wavax.balanceOf(initiatorPayout), commissionAmount);
        assertEq(wavax.balanceOf(keeper), 0);
    }
}
