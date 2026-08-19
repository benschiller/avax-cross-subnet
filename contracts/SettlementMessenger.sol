// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@teleporter/teleporter/ITeleporterMessenger.sol";
import "@teleporter/teleporter/ITeleporterReceiver.sol";
import "./TradeEscrow.sol";

contract SettlementMessenger is ITeleporterReceiver {
    uint8 internal constant MESSAGE_TYPE_CREATE_ORDER = 1;

    ITeleporterMessenger public immutable teleporterMessenger;
    bytes32 public immutable initiatorBlockchainID;
    address public initiatorMessenger;
    TradeEscrow public tradeEscrow;

    address public immutable deployer;
    bool public escrowSet;
    bool public initiatorMessengerSet;

    event OrderReceived(bytes32 indexed orderId);
    event EscrowSet(address indexed tradeEscrow);
    event InitiatorMessengerSet(address indexed initiatorMessenger);

    error UnauthorizedTeleporter();
    error InvalidSourceBlockchain();
    error InvalidOriginSender();
    error InvalidMessageType();
    error EscrowAlreadySet();
    error InitiatorMessengerAlreadySet();

    constructor(address _teleporterMessenger, bytes32 _initiatorBlockchainID, address _initiatorMessenger) {
        require(_teleporterMessenger != address(0), "SettlementMessenger: zero teleporter");
        require(_initiatorBlockchainID != bytes32(0), "SettlementMessenger: zero blockchainID");
        teleporterMessenger = ITeleporterMessenger(_teleporterMessenger);
        initiatorBlockchainID = _initiatorBlockchainID;
        initiatorMessenger = _initiatorMessenger;
        deployer = msg.sender;
    }

    function setInitiatorMessenger(address _initiatorMessenger) external {
        require(msg.sender == deployer, "SettlementMessenger: not deployer");
        require(_initiatorMessenger != address(0), "SettlementMessenger: zero initiatorMessenger");
        if (initiatorMessengerSet) {
            revert InitiatorMessengerAlreadySet();
        }
        initiatorMessenger = _initiatorMessenger;
        initiatorMessengerSet = true;
        emit InitiatorMessengerSet(_initiatorMessenger);
    }

    function setEscrow(address _tradeEscrow) external {
        require(msg.sender == deployer, "SettlementMessenger: not deployer");
        require(_tradeEscrow != address(0), "SettlementMessenger: zero escrow");
        if (escrowSet) {
            revert EscrowAlreadySet();
        }
        tradeEscrow = TradeEscrow(_tradeEscrow);
        escrowSet = true;
        emit EscrowSet(_tradeEscrow);
    }

    function receiveTeleporterMessage(
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        bytes calldata message
    ) external {
        if (msg.sender != address(teleporterMessenger)) {
            revert UnauthorizedTeleporter();
        }
        if (sourceBlockchainID != initiatorBlockchainID) {
            revert InvalidSourceBlockchain();
        }
        require(initiatorMessengerSet, "SettlementMessenger: initiator messenger not set");
        if (originSenderAddress != initiatorMessenger) {
            revert InvalidOriginSender();
        }
        require(escrowSet, "SettlementMessenger: escrow not set");

        (
            uint8 messageType,
            bytes32 orderId,
            address tokenIn,
            address tokenOut,
            uint256 amountIn,
            uint256 minAmountOut,
            uint256 commissionBps,
            address initiatorPayout
        ) = abi.decode(message, (uint8, bytes32, address, address, uint256, uint256, uint256, address));

        if (messageType != MESSAGE_TYPE_CREATE_ORDER) {
            revert InvalidMessageType();
        }
        require(commissionBps <= 10_000, "SettlementMessenger: invalid bps");

        tradeEscrow.openLeg(orderId, tokenIn, tokenOut, amountIn, minAmountOut, initiatorPayout);

        emit OrderReceived(orderId);
    }
}
