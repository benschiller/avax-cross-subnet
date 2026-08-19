// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TradeEscrow {
    using SafeERC20 for IERC20;

    error Unauthorized();
    error DuplicateOrder();
    error NotFunded();
    error NotExecuted();
    error AlreadyExecuted();
    error AlreadyPaid();
    error SlippageFailed();

    struct Trade {
        address tokenIn;
        address tokenOut;
        address initiatorPayout;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 commissionAmount;
        bool funded;
        bool executed;
        bool commissionPaid;
    }

    address public immutable executor;
    address public immutable settlementMessenger;
    uint256 public immutable commissionBps;

    mapping(bytes32 => Trade) public trades;

    event TradeFunded(
        bytes32 indexed orderId,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 commissionAmount,
        uint256 tradeAmount,
        address initiatorPayout
    );
    event TradeExecuted(bytes32 indexed orderId, uint256 amountOut);
    event CommissionPaid(bytes32 indexed orderId, address indexed initiatorPayout, uint256 commissionAmount);

    modifier onlyExecutorOrMessenger() {
        if (msg.sender != executor && msg.sender != settlementMessenger) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyExecutor() {
        if (msg.sender != executor) {
            revert Unauthorized();
        }
        _;
    }

    constructor(address _executor, address _settlementMessenger, uint256 _commissionBps) {
        require(_executor != address(0), "TradeEscrow: zero executor");
        require(_settlementMessenger != address(0), "TradeEscrow: zero settlementMessenger");
        require(_commissionBps > 0 && _commissionBps <= 10_000, "TradeEscrow: invalid bps");
        executor = _executor;
        settlementMessenger = _settlementMessenger;
        commissionBps = _commissionBps;
    }

    function openLeg(
        bytes32 orderId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address initiatorPayout
    ) external onlyExecutorOrMessenger {
        if (trades[orderId].funded) {
            revert DuplicateOrder();
        }
        require(tokenIn != address(0), "TradeEscrow: zero tokenIn");
        require(tokenOut != address(0), "TradeEscrow: zero tokenOut");
        require(amountIn > 0, "TradeEscrow: zero amountIn");
        require(initiatorPayout != address(0), "TradeEscrow: zero initiatorPayout");

        uint256 commissionAmount = (amountIn * commissionBps) / 10_000;
        uint256 tradeAmount = amountIn - commissionAmount;

        // Pull the full input from the executor.
        IERC20(tokenIn).safeTransferFrom(executor, address(this), amountIn);

        trades[orderId] = Trade({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            initiatorPayout: initiatorPayout,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            commissionAmount: commissionAmount,
            funded: true,
            executed: false,
            commissionPaid: false
        });

        // Return the tradeable amount to the executor for the swap.
        if (tradeAmount > 0) {
            IERC20(tokenIn).safeTransfer(executor, tradeAmount);
        }

        emit TradeFunded(orderId, tokenIn, tokenOut, amountIn, commissionAmount, tradeAmount, initiatorPayout);
    }

    function closeOpenLeg(bytes32 orderId) external onlyExecutor {
        Trade storage trade = trades[orderId];
        if (!trade.funded) {
            revert NotFunded();
        }
        if (trade.executed) {
            revert AlreadyExecuted();
        }

        uint256 outputBalance = IERC20(trade.tokenOut).balanceOf(address(this));
        if (outputBalance < trade.minAmountOut) {
            revert SlippageFailed();
        }

        trade.executed = true;

        // Transfer the output to the executor so the escrow retains no residual tokenOut.
        IERC20(trade.tokenOut).safeTransfer(executor, outputBalance);

        emit TradeExecuted(orderId, outputBalance);
    }

    function payOpenCommission(bytes32 orderId) external {
        Trade storage trade = trades[orderId];
        if (!trade.funded) {
            revert NotFunded();
        }
        if (!trade.executed) {
            revert NotExecuted();
        }
        if (trade.commissionPaid) {
            revert AlreadyPaid();
        }

        trade.commissionPaid = true;

        IERC20(trade.tokenIn).safeTransfer(trade.initiatorPayout, trade.commissionAmount);

        emit CommissionPaid(orderId, trade.initiatorPayout, trade.commissionAmount);
    }
}
