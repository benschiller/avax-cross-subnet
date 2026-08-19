import "dotenv/config";
import { ethers } from "ethers";
import * as fs from "fs";
import * as path from "path";
import { spawn, execSync } from "child_process";

/**
 * Run the full cross-L1 demo on Avalanche local subnets.
 *
 * Requires:
 *  - .env and deployed.json populated by `npm run deploy:local`
 *  - ICM relayer running (auto-started if AUTO_RELAY=true)
 */

const ORDER_ID = ethers.keccak256(
  ethers.toUtf8Bytes(`cross-subnet-order-avalanche-${Date.now()}`)
);

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

async function waitForRelay(
  tradeEscrow: ethers.Contract,
  orderId: string,
  timeoutSeconds = 120
): Promise<boolean> {
  const deadline = Date.now() + timeoutSeconds * 1000;
  while (Date.now() < deadline) {
    const trade = await tradeEscrow.trades(orderId);
    if (trade.funded) {
      return true;
    }
    await new Promise((r) => setTimeout(r, 2000));
  }
  return false;
}

async function main() {
  if (!fs.existsSync("deployed.json")) {
    console.error("deployed.json not found. Run `npm run deploy:local` first.");
    process.exit(1);
  }

  const deployed = JSON.parse(fs.readFileSync("deployed.json", "utf8"));
  const initiatorRpc = deployed.initiator.rpcUrl;
  const settlementRpc = deployed.settlement.rpcUrl;

  const initiatorProvider = new ethers.JsonRpcProvider(initiatorRpc);
  const settlementProvider = new ethers.JsonRpcProvider(settlementRpc);

  const initiator = new ethers.Wallet(process.env.INITIATOR_PRIVATE_KEY!, initiatorProvider);
  const executor = new ethers.Wallet(process.env.EXECUTOR_PRIVATE_KEY!, settlementProvider);
  const keeper = new ethers.Wallet(process.env.KEEPER_PRIVATE_KEY!, settlementProvider);

  const initiatorMessenger = new ethers.Contract(deployed.initiator.initiatorMessenger, loadAbi("InitiatorMessenger"), initiator);
  const settlementMessenger = new ethers.Contract(deployed.settlement.settlementMessenger, loadAbi("SettlementMessenger"), executor);
  const tradeEscrow = new ethers.Contract(deployed.settlement.tradeEscrow, loadAbi("TradeEscrow"), executor);
  const mockWavax = new ethers.Contract(deployed.settlement.mockWAVAX, loadAbi("MockWAVAX"), executor);
  const mockUsdc = new ethers.Contract(deployed.settlement.mockUSDC, loadAbi("MockUSDC"), executor);
  const mockDex = new ethers.Contract(deployed.settlement.mockDEX, loadAbi("MockDEX"), executor);

  const amountIn = BigInt(process.env.DEMO_AMOUNT_IN!);
  const minAmountOut = BigInt(process.env.DEMO_MIN_AMOUNT_OUT!);
  const commissionBps = parseInt(process.env.COMMISSION_BPS || "5", 10);
  const initiatorPayout = process.env.INITIATOR_PAYOUT_ADDRESS!;

  console.log("Initiator:", initiator.address);
  console.log("Executor:", executor.address);
  console.log("Keeper:", keeper.address);
  console.log("Initiator Payout:", initiatorPayout);
  console.log("");

  // Start relayer if configured
  let relayerProcess: ReturnType<typeof spawn> | null = null;
  if (process.env.AUTO_RELAY === "true") {
    try {
      execSync("pgrep -f 'icm-relayer.*icm-relayer-config.json'", { stdio: "ignore" });
      console.log("Relayer already running.");
    } catch {
      console.log("Starting ICM relayer...");
      relayerProcess = spawn("~/.avalanche-cli/bin/icm-relayer/icm-relayer", ["--config-file", "icm-relayer-config.json"], {
        detached: true,
        stdio: "ignore",
        shell: true,
      });
      relayerProcess.unref();
      await new Promise((r) => setTimeout(r, 5000));
    }
  }

  // --- Fund and approve on Settlement Subnet ---
  console.log("--- Funding & approvals ---");
  let nonce = await executor.getNonce();
  await (await mockWavax.mint(executor.address, amountIn, { nonce: nonce++ })).wait();
  await (await mockWavax.approve(deployed.settlement.tradeEscrow, amountIn, { nonce: nonce++ })).wait();
  await (await mockUsdc.mint(deployed.settlement.mockDEX, minAmountOut * 2n, { nonce: nonce++ })).wait();
  console.log("Executor mWAVAX:", fmtEther(await mockWavax.balanceOf(executor.address), 18));
  console.log("MockDEX mUSDC:", fmtEther(await mockUsdc.balanceOf(deployed.settlement.mockDEX), 6));
  console.log("");

  // --- Initiator sends order ---
  console.log("--- Initiator sends order ---");
  console.log("Order ID:", ORDER_ID);
  let nonceInit = await initiator.getNonce();
  const tx = await initiatorMessenger.sendOrder(
    ORDER_ID,
    deployed.settlement.mockWAVAX,
    deployed.settlement.mockUSDC,
    amountIn,
    minAmountOut,
    commissionBps,
    initiatorPayout,
    { nonce: nonceInit++ }
  );
  await tx.wait();
  console.log("Order sent. Tx:", tx.hash);
  console.log("");

  // --- Wait for relayer ---
  console.log("--- Waiting for ICM relayer to deliver message ---");
  const delivered = await waitForRelay(tradeEscrow, ORDER_ID);
  if (!delivered) {
    console.error("Timed out waiting for cross-chain message delivery. Is the relayer running?");
    process.exit(1);
  }
  console.log("Message delivered and escrow leg opened.");
  console.log("");

  // --- Executor executes trade ---
  console.log("--- Executor executes trade ---");
  const trade = await tradeEscrow.trades(ORDER_ID);
  console.log("Commission:", fmtEther(trade.commissionAmount, 18), "mWAVAX");
  console.log("Trade amount:", fmtEther(trade.amountIn - trade.commissionAmount, 18), "mWAVAX");

  nonce = await executor.getNonce();
  const tradeAmount = trade.amountIn - trade.commissionAmount;
  await (await mockWavax.approve(deployed.settlement.mockDEX, tradeAmount, { nonce: nonce++ })).wait();
  await (await mockDex.swap(deployed.settlement.mockWAVAX, deployed.settlement.mockUSDC, tradeAmount, minAmountOut, executor.address, { nonce: nonce++ })).wait();
  await (await mockUsdc.transfer(deployed.settlement.tradeEscrow, minAmountOut, { nonce: nonce++ })).wait();
  await (await tradeEscrow.closeOpenLeg(ORDER_ID, { nonce: nonce++ })).wait();
  console.log("Executor mUSDC after swap:", fmtEther(await mockUsdc.balanceOf(executor.address), 6));
  console.log("Trade closed");
  console.log("");

  // --- Keeper triggers payout ---
  console.log("--- Keeper triggers payout ---");
  const keeperNonce = await keeper.getNonce();
  await (await tradeEscrow.connect(keeper).payOpenCommission(ORDER_ID, { nonce: keeperNonce })).wait();
  console.log("Commission paid");
  console.log("");

  // --- Final balances ---
  console.log("--- Final balances ---");
  console.log("Escrow mWAVAX:", fmtEther(await mockWavax.balanceOf(deployed.settlement.tradeEscrow), 18));
  console.log("Escrow mUSDC:", fmtEther(await mockUsdc.balanceOf(deployed.settlement.tradeEscrow), 6));
  console.log("Initiator Payout mWAVAX:", fmtEther(await mockWavax.balanceOf(initiatorPayout), 18));
  console.log("Keeper mWAVAX:", fmtEther(await mockWavax.balanceOf(keeper.address), 18));
  console.log("Executor mWAVAX:", fmtEther(await mockWavax.balanceOf(executor.address), 18));
  console.log("Executor mUSDC:", fmtEther(await mockUsdc.balanceOf(executor.address), 6));

  if (relayerProcess) {
    console.log("");
    console.log("Stopping relayer...");
    relayerProcess.kill();
  }

  console.log("");
  console.log("Demo completed successfully.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
