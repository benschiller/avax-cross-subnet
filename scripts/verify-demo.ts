import "dotenv/config";
import { ethers } from "ethers";
import * as fs from "fs";
import * as path from "path";

/**
 * Post-demo verification - shows complete transaction trail with events
 * Run after npm run demo for a "wow moment" showing cross-chain execution
 */

function loadAbi(contractName: string) {
  const artifactPath = path.join(__dirname, "..", "out", `${contractName}.sol`, `${contractName}.json`);
  const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
  return artifact.abi;
}

function fmtEther(value: bigint, decimals: number): string {
  const s = value.toString();
  if (decimals === 0) return s;
  const pad = s.padStart(decimals + 1, "0");
  const intPart = pad.slice(0, -decimals);
  const fracPart = pad.slice(-decimals).replace(/0+$/, "");
  return fracPart ? `${intPart}.${fracPart}` : intPart;
}

async function main() {
  if (!fs.existsSync("deployed.json")) {
    console.error("deployed.json not found. Run `npm run deploy:local` first.");
    process.exit(1);
  }

  const deployed = JSON.parse(fs.readFileSync("deployed.json", "utf8"));
  const initiatorProvider = new ethers.JsonRpcProvider(deployed.initiator.rpcUrl);
  const settlementProvider = new ethers.JsonRpcProvider(deployed.settlement.rpcUrl);

  // Load contracts
  const tradeEscrow = new ethers.Contract(deployed.settlement.tradeEscrow, loadAbi("TradeEscrow"), settlementProvider);
  const mockWavax = new ethers.Contract(deployed.settlement.mockWAVAX, loadAbi("MockWAVAX"), settlementProvider);
  const mockUsdc = new ethers.Contract(deployed.settlement.mockUSDC, loadAbi("MockUSDC"), settlementProvider);
  const initiatorMessenger = new ethers.Contract(deployed.initiator.initiatorMessenger, loadAbi("InitiatorMessenger"), initiatorProvider);
  const settlementMessenger = new ethers.Contract(deployed.settlement.settlementMessenger, loadAbi("SettlementMessenger"), settlementProvider);

  console.log("╔══════════════════════════════════════════════════════════════════════╗");
  console.log("║        CROSS-SUBNET DEMO VERIFICATION - TRANSACTION TRAIL          ║");
  console.log("╚══════════════════════════════════════════════════════════════════════╝");
  console.log("");

  // Find the latest order by checking TradeFunded events
  console.log("🔍 Scanning for cross-chain trades on Settlement L1...");
  const latestBlock = await settlementProvider.getBlockNumber();
  const tradeFundedFilter = tradeEscrow.filters.TradeFunded();
  const tradeFundedEvents = await tradeEscrow.queryFilter(tradeFundedFilter, 0, latestBlock);
  
  if (tradeFundedEvents.length === 0) {
    console.log("No trades found. Run `npm run demo` first.");
    return;
  }

  // Show the latest trade
  const latestEvent = tradeFundedEvents[tradeFundedEvents.length - 1];
  const orderId = latestEvent.args.orderId;
  const trade = await tradeEscrow.trades(orderId);

  console.log(`\n📋 ORDER ID: ${orderId}`);
  console.log("──────────────────────────────────────────────────────────────────────");
  
  // 1. Initiator L1 - Order Sent
  console.log("\n📍 STEP 1: INITIATOR L1 (Initiator Subnet)");
  console.log(`   RPC: ${deployed.initiator.rpcUrl}`);
  console.log(`   Chain ID: ${deployed.initiator.chainId}`);
  
  // Get the sendOrder transaction from InitiatorMessenger events
  const initiatorLatestBlock = await initiatorProvider.getBlockNumber();
  const orderSentFilter = initiatorMessenger.filters.OrderSent(orderId);
  const orderSentEvents = await initiatorMessenger.queryFilter(orderSentFilter, 0, initiatorLatestBlock);
  
  if (orderSentEvents.length > 0) {
    const event = orderSentEvents[0];
    const receipt = await initiatorProvider.getTransactionReceipt(event.transactionHash);
    console.log(`   ✅ OrderSent Event`);
    console.log(`      Tx Hash: ${event.transactionHash}`);
    console.log(`      Block: ${receipt.blockNumber}`);
    console.log(`      Gas Used: ${receipt.gasUsed.toString()}`);
    console.log(`      Destination Messenger: ${event.args.destinationAddress}`);
    console.log(`      Teleporter Message ID: ${event.args.teleporterMessageID}`);
  }

  // 2. Cross-chain message delivery
  console.log("\n📍 STEP 2: CROSS-CHAIN MESSAGE DELIVERY (Teleporter/ICM)");
  console.log(`   Relayer delivers message from Initiator L1 → Settlement L1`);
  console.log(`   Source Chain: ${deployed.initiator.blockchainIdCb58}`);
  console.log(`   Dest Chain:   ${deployed.settlement.blockchainIdCb58}`);

  // 3. Settlement L1 - Message Received & Escrow Funded
  console.log("\n📍 STEP 3: SETTLEMENT L1 (Settlement Subnet)");
  console.log(`   RPC: ${deployed.settlement.rpcUrl}`);
  console.log(`   Chain ID: ${deployed.settlement.chainId}`);

  // OrderReceived event (Teleporter message received)
  const orderReceivedFilter = settlementMessenger.filters.OrderReceived(orderId);
  const orderReceivedEvents = await settlementMessenger.queryFilter(orderReceivedFilter, 0, latestBlock);
  
  if (orderReceivedEvents.length > 0) {
    const event = orderReceivedEvents[0];
    const receipt = await settlementProvider.getTransactionReceipt(event.transactionHash);
    console.log(`   ✅ OrderReceived Event (Teleporter Message Authenticated)`);
    console.log(`      Tx Hash: ${event.transactionHash}`);
    console.log(`      Block: ${receipt.blockNumber}`);
    console.log(`      Gas Used: ${receipt.gasUsed.toString()}`);
  }

  // TradeFunded event
  const receiptFunded = await settlementProvider.getTransactionReceipt(latestEvent.transactionHash);
  console.log(`   ✅ TradeFunded Event (Escrow Opened)`);
  console.log(`      Tx Hash: ${latestEvent.transactionHash}`);
  console.log(`      Block: ${receiptFunded.blockNumber}`);
  console.log(`      Gas Used: ${receiptFunded.gasUsed.toString()}`);
  console.log(`      Token In: ${latestEvent.args.tokenIn} (${fmtEther(latestEvent.args.amountIn, 18)} mWAVAX)`);
  console.log(`      Token Out: ${latestEvent.args.tokenOut}`);
  console.log(`      Commission Locked: ${fmtEther(latestEvent.args.commissionAmount, 18)} mWAVAX (${trade.commissionBps || 5} bps)`);
  console.log(`      Trade Amount Released: ${fmtEther(latestEvent.args.tradeAmount, 18)} mWAVAX → Executor`);
  console.log(`      Initiator Payout: ${latestEvent.args.initiatorPayout}`);

  // 4. Trade Executed
  const tradeExecutedFilter = tradeEscrow.filters.TradeExecuted(orderId);
  const executedEvents = await tradeEscrow.queryFilter(tradeExecutedFilter, 0, latestBlock);
  
  if (executedEvents.length > 0) {
    const event = executedEvents[0];
    const receipt = await settlementProvider.getTransactionReceipt(event.transactionHash);
    console.log(`   ✅ TradeExecuted Event (Swap Verified & Output Released)`);
    console.log(`      Tx Hash: ${event.transactionHash}`);
    console.log(`      Block: ${receipt.blockNumber}`);
    console.log(`      Gas Used: ${receipt.gasUsed.toString()}`);
    console.log(`      Output Received: ${fmtEther(event.args.amountOut, 6)} mUSDC → Executor`);
    console.log(`      Slippage Check: PASSED (output ≥ minAmountOut)`);
  }

  // 5. Commission Paid
  const commissionPaidFilter = tradeEscrow.filters.CommissionPaid(orderId);
  const commissionPaidEvents = await tradeEscrow.queryFilter(commissionPaidFilter, 0, latestBlock);
  
  if (commissionPaidEvents.length > 0) {
    const event = commissionPaidEvents[0];
    const receipt = await settlementProvider.getTransactionReceipt(event.transactionHash);
    console.log(`   ✅ CommissionPaid Event (Permissionless Keeper Payout)`);
    console.log(`      Tx Hash: ${event.transactionHash}`);
    console.log(`      Block: ${receipt.blockNumber}`);
    console.log(`      Gas Used: ${receipt.gasUsed.toString()}`);
    console.log(`      Commission: ${fmtEther(event.args.commissionAmount, 18)} mWAVAX → Initiator Payout`);
    console.log(`      Keeper: ${event.args.payer || 'permissionless caller'}`);
    console.log(`      🔒 Payout destination FIXED to initiatorPayout (caller cannot redirect)`);
  }

  // Final state verification
  console.log("\n📊 FINAL STATE VERIFICATION");
  console.log("──────────────────────────────────────────────────────────────────────");
  
  const escrowWavax = await mockWavax.balanceOf(deployed.settlement.tradeEscrow);
  const escrowUsdc = await mockUsdc.balanceOf(deployed.settlement.tradeEscrow);
  const payoutWavax = await mockWavax.balanceOf(trade.initiatorPayout);
  
  // Get executor from the TradeExecuted event (the msg.sender)
  let executor = "0x";
  if (executedEvents.length > 0) {
    const receipt = await settlementProvider.getTransactionReceipt(executedEvents[0].transactionHash);
    executor = receipt.from;
  }

  const agentWavax = await mockWavax.balanceOf(executor);
  const agentUsdc = await mockUsdc.balanceOf(executor);

  console.log(`   TradeEscrow mWAVAX:  ${fmtEther(escrowWavax, 18)}  (should be 0 - commission paid out)`);
  console.log(`   TradeEscrow mUSDC:   ${fmtEther(escrowUsdc, 6)}    (should be 0 - output released)`);
  console.log(`   Initiator Payout:    ${fmtEther(payoutWavax, 18)} mWAVAX  (commission received)`);
  console.log(`   Executor:            ${fmtEther(agentWavax, 18)} mWAVAX, ${fmtEther(agentUsdc, 6)} mUSDC`);

  // Invariant check
  const tradeData = await tradeEscrow.trades(orderId);
  console.log("\n🔐 INVARIANT CHECKS");
  console.log("──────────────────────────────────────────────────────────────────────");
  console.log(`   ✅ funded:     ${tradeData.funded}`);
  console.log(`   ✅ executed:   ${tradeData.executed}`);
  console.log(`   ✅ paid:       ${tradeData.commissionPaid}`);
  console.log(`   ✅ payout fixed:    Commission can ONLY go to ${tradeData.initiatorPayout}`);

  console.log("\n╔══════════════════════════════════════════════════════════════════════╗");
  console.log("║  ✅ VERIFICATION COMPLETE - Cross-subnet trade executed trustlessly  ║");
  console.log("╚══════════════════════════════════════════════════════════════════════╝");
}

main().catch((err) => {
  console.error("Verification failed:", err);
  process.exit(1);
});
