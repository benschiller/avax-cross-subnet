import "dotenv/config";
import { ethers } from "ethers";
import * as fs from "fs";
import * as path from "path";

/**
 * Deploy the project contracts to two Avalanche L1s.
 *
 * Assumes:
 *  - deployed.json is populated with RPC endpoints, blockchain IDs, and Teleporter addresses.
 *  - Both L1s are running and the deployer key has native gas tokens.
 */

function loadAbi(contractName: string) {
  const artifactPath = path.join(__dirname, "..", "out", `${contractName}.sol`, `${contractName}.json`);
  const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
  return artifact.abi;
}

function loadBytecode(contractName: string) {
  const artifactPath = path.join(__dirname, "..", "out", `${contractName}.sol`, `${contractName}.json`);
  const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
  return artifact.bytecode.object;
}

async function deployContract(
  deployer: ethers.Wallet,
  name: string,
  args: any[] = [],
  nonce?: number
): Promise<ethers.Contract> {
  const factory = new ethers.ContractFactory(loadAbi(name), loadBytecode(name), deployer);
  const txArgs: any = {};
  if (nonce !== undefined) txArgs.nonce = nonce;
  const contract = await factory.deploy(...args, txArgs);
  await contract.waitForDeployment();
  const address = await contract.getAddress();
  console.log(`  ${name}: ${address}`);
  return contract;
}

async function sendTx(wallet: ethers.Wallet, contract: ethers.Contract, method: string, args: any[], nonce?: number) {
  const txArgs: any = {};
  if (nonce !== undefined) txArgs.nonce = nonce;
  const tx = await contract[method](...args, txArgs);
  await tx.wait();
}

async function main() {
  if (!fs.existsSync("deployed.json")) {
    throw new Error("deployed.json not found. Run deploy:local first.");
  }

  const deployed = JSON.parse(fs.readFileSync("deployed.json", "utf8"));

  const initiatorRpc = deployed.initiator.rpcUrl;
  const settlementRpc = deployed.settlement.rpcUrl;
  const initiatorBlockchainId = deployed.initiator.blockchainId;
  const settlementBlockchainId = deployed.settlement.blockchainId;
  const initiatorTeleporter = deployed.initiator.teleporterMessenger;
  const settlementTeleporter = deployed.settlement.teleporterMessenger;
  const deployerKey = process.env.DEPLOYER_PRIVATE_KEY;
  const initiatorKey = process.env.INITIATOR_PRIVATE_KEY || deployerKey;
  const executorKey = process.env.EXECUTOR_PRIVATE_KEY || deployerKey;
  const keeperKey = process.env.KEEPER_PRIVATE_KEY || deployerKey;
  const commissionBps = parseInt(process.env.COMMISSION_BPS || "5", 10);

  if (!initiatorRpc || !settlementRpc || !deployerKey) {
    throw new Error("Missing required network config in deployed.json or DEPLOYER_PRIVATE_KEY in .env");
  }

  const initiatorProvider = new ethers.JsonRpcProvider(initiatorRpc);
  const settlementProvider = new ethers.JsonRpcProvider(settlementRpc);

  const deployerInitiator = new ethers.Wallet(deployerKey, initiatorProvider);
  const deployerSettlement = new ethers.Wallet(deployerKey, settlementProvider);

  console.log("Deployer:", deployerSettlement.address);
  console.log("Initiator:", new ethers.Wallet(initiatorKey).address);
  console.log("Executor:", new ethers.Wallet(executorKey).address);
  console.log("Keeper:", new ethers.Wallet(keeperKey).address);
  console.log("Initiator Payout:", process.env.INITIATOR_PAYOUT_ADDRESS);
  console.log("");

  // --- Deploy on Settlement Subnet ---
  console.log("--- Deploying on Settlement Subnet ---");
  let nonceExec = await deployerSettlement.getNonce();
  const mockWavax = await deployContract(deployerSettlement, "MockWAVAX", [], nonceExec++);
  const mockUsdc = await deployContract(deployerSettlement, "MockUSDC", [], nonceExec++);
  const mockDex = await deployContract(deployerSettlement, "MockDEX", [], nonceExec++);
  const settlementMessenger = await deployContract(
    deployerSettlement,
    "SettlementMessenger",
    [settlementTeleporter, initiatorBlockchainId, ethers.ZeroAddress],
    nonceExec++
  );
  const executorAddr = new ethers.Wallet(executorKey).address;
  const tradeEscrow = await deployContract(
    deployerSettlement,
    "TradeEscrow",
    [executorAddr, await settlementMessenger.getAddress(), commissionBps],
    nonceExec++
  );

  // Wire SettlementMessenger
  await sendTx(deployerSettlement, settlementMessenger, "setEscrow", [await tradeEscrow.getAddress()], nonceExec++);

  // --- Deploy on Initiator Subnet ---
  console.log("--- Deploying on Initiator Subnet ---");
  let nonceInit = await deployerInitiator.getNonce();
  const initiatorMessenger = await deployContract(
    deployerInitiator,
    "InitiatorMessenger",
    [initiatorTeleporter, settlementBlockchainId, await settlementMessenger.getAddress(), process.env.INITIATOR_PAYOUT_ADDRESS],
    nonceInit++
  );

  // Wire initiator messenger address back into SettlementMessenger
  await sendTx(deployerSettlement, settlementMessenger, "setInitiatorMessenger", [await initiatorMessenger.getAddress()], nonceExec++);

  // --- Update deployed.json with contract addresses ---
  deployed.settlement.mockWAVAX = await mockWavax.getAddress();
  deployed.settlement.mockUSDC = await mockUsdc.getAddress();
  deployed.settlement.mockDEX = await mockDex.getAddress();
  deployed.settlement.tradeEscrow = await tradeEscrow.getAddress();
  deployed.settlement.settlementMessenger = await settlementMessenger.getAddress();
  deployed.initiator.initiatorMessenger = await initiatorMessenger.getAddress();

  fs.writeFileSync("deployed.json", JSON.stringify(deployed, null, 2));
  console.log("");
  console.log("Deployment details written to deployed.json");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
