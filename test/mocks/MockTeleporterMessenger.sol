// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@teleporter/teleporter/ITeleporterMessenger.sol";

contract MockTeleporterMessenger is ITeleporterMessenger {
    TeleporterMessageInput public lastMessageInput;

    function sendCrossChainMessage(TeleporterMessageInput calldata messageInput)
        external
        returns (bytes32 messageID)
    {
        lastMessageInput = messageInput;
        messageID = keccak256(
            abi.encodePacked(
                messageInput.destinationBlockchainID,
                messageInput.destinationAddress,
                messageInput.message,
                block.number
            )
        );
    }

    function receiveCrossChainMessage(uint32, address) external pure {}
    function retrySendCrossChainMessage(TeleporterMessage calldata) external pure {}
    function addFeeAmount(bytes32, address, uint256) external pure {}
    function retryMessageExecution(bytes32, TeleporterMessage calldata) external pure {}

    function sendSpecifiedReceipts(bytes32, bytes32[] calldata, TeleporterFeeInfo calldata, address[] calldata)
        external
        pure
        returns (bytes32)
    {
        return bytes32(0);
    }

    function redeemRelayerRewards(address) external pure {}
    function getMessageHash(bytes32) external pure returns (bytes32) {
        return bytes32(0);
    }

    function messageReceived(bytes32) external pure returns (bool) {
        return false;
    }

    function getRelayerRewardAddress(bytes32) external pure returns (address) {
        return address(0);
    }

    function checkRelayerRewardAmount(address, address) external pure returns (uint256) {
        return 0;
    }

    function getFeeInfo(bytes32) external pure returns (address, uint256) {
        return (address(0), 0);
    }

    function getNextMessageID(bytes32) external pure returns (bytes32) {
        return bytes32(0);
    }

    function getReceiptQueueSize(bytes32) external pure returns (uint256) {
        return 0;
    }

    function getReceiptAtIndex(bytes32, uint256) external pure returns (TeleporterMessageReceipt memory) {
        return TeleporterMessageReceipt(0, address(0));
    }
}
