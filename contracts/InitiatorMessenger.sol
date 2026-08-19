// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@teleporter/teleporter/ITeleporterMessenger.sol";

contract InitiatorMessenger {
    uint8 internal constant MESSAGE_TYPE_CREATE_ORDER = 1;

    ITeleporterMessenger public immutable teleporterMessenger;
    bytes32 public immutable settlementBlockchainID;
    address public immutable settlementMessenger;
    address public immutable initiatorPayout;

    event OrderSent(
        bytes32 indexed orderId,
        bytes32 indexed destinationBlockchainID,
        address indexed destinationAddress,
        bytes32 teleporterMessageID
    );

    constructor(
        address _teleporterMessenger,
        bytes32 _settlementBlockchainID,
        address _settlementMessenger,
        address _initiatorPayout
    ) {
        require(_teleporterMessenger != address(0), "InitiatorMessenger: zero teleporter");
        require(_settlementBlockchainID != bytes32(0), "InitiatorMessenger: zero blockchainID");
        require(_settlementMessenger != address(0), "InitiatorMessenger: zero settlementMessenger");
        require(_initiatorPayout != address(0), "InitiatorMessenger: zero initiatorPayout");
        teleporterMessenger = ITeleporterMessenger(_teleporterMessenger);
        settlementBlockchainID = _settlementBlockchainID;
        settlementMessenger = _settlementMessenger;
        initiatorPayout = _initiatorPayout;
    }

    function sendOrder(
        bytes32 orderId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 commissionBps,
        address _initiatorPayout
    ) external returns (bytes32) {
        require(orderId != bytes32(0), "InitiatorMessenger: zero orderId");

        bytes memory message = abi.encode(
            MESSAGE_TYPE_CREATE_ORDER, orderId, tokenIn, tokenOut, amountIn, minAmountOut, commissionBps, _initiatorPayout
        );

        TeleporterMessageInput memory input = TeleporterMessageInput({
            destinationBlockchainID: settlementBlockchainID,
            destinationAddress: settlementMessenger,
            feeInfo: TeleporterFeeInfo({feeTokenAddress: address(0), amount: 0}),
            requiredGasLimit: 2_000_000,
            allowedRelayerAddresses: new address[](0),
            message: message
        });

        bytes32 messageID = teleporterMessenger.sendCrossChainMessage(input);

        emit OrderSent(orderId, settlementBlockchainID, settlementMessenger, messageID);

        return messageID;
    }
}
