import "dotenv/config";
import { ethers } from "ethers";
import * as fs from "fs";

/**
 * Bootstrap helper for the Avalanche CLI local-subnet path.
 * Reads deployed.json and verifies that the configured contracts exist on both chains.
 */

async function main() {
  if (!fs.existsSync("deployed.json")) {
    console.error("deployed.json not found. Copy deployed.json.example and fill in the addresses first.");
    process.exit(1);
  }

  const deployed = JSON.parse(fs.readFileSync("deployed.json", "utf8"));
  const initiatorProvider = new ethers.JsonRpcProvider(deployed.initiator.rpcUrl);
  const settlementProvider = new ethers.JsonRpcProvider(deployed.settlement.rpcUrl);

  console.log("Verifying L1 connectivity and contract deployments...\n");

  // Verify Initiator L1 connectivity
  const initiatorBlock = await initiatorProvider.getBlockNumber();
  console.log(`✓ Initiator L1 (${deployed.initiator.rpcUrl}) - Block: ${initiatorBlock}`);

  // Verify Settlement L1 connectivity
  const settlementBlock = await settlementProvider.getBlockNumber();
  console.log(`✓ Settlement L1 (${deployed.settlement.rpcUrl}) - Block: ${settlementBlock}`);

  // Verify contracts on Initiator L1
  const initiatorCode = await initiatorProvider.getCode(deployed.initiator.initiatorMessenger);
  if (initiatorCode === "0x") {
    throw new Error(`InitiatorMessenger not deployed at ${deployed.initiator.initiatorMessenger}`);
  }
  console.log(`✓ InitiatorMessenger deployed at ${deployed.initiator.initiatorMessenger}`);

  // Verify contracts on Settlement L1
  const settlementCode = await settlementProvider.getCode(deployed.settlement.settlementMessenger);
  if (settlementCode === "0x") {
    throw new Error(`SettlementMessenger not deployed at ${deployed.settlement.settlementMessenger}`);
  }
  console.log(`✓ SettlementMessenger deployed at ${deployed.settlement.settlementMessenger}`);

  const escrowCode = await settlementProvider.getCode(deployed.settlement.tradeEscrow);
  if (escrowCode === "0x") {
    throw new Error(`TradeEscrow not deployed at ${deployed.settlement.tradeEscrow}`);
  }
  console.log(`✓ TradeEscrow deployed at ${deployed.settlement.tradeEscrow}`);

  // Verify mocks on Settlement L1
  const mockWavaxCode = await settlementProvider.getCode(deployed.settlement.mockWAVAX);
  if (mockWavaxCode === "0x") {
    throw new Error(`MockWAVAX not deployed at ${deployed.settlement.mockWAVAX}`);
  }
  console.log(`✓ MockWAVAX deployed at ${deployed.settlement.mockWAVAX}`);

  const mockUsdcCode = await settlementProvider.getCode(deployed.settlement.mockUSDC);
  if (mockUsdcCode === "0x") {
    throw new Error(`MockUSDC not deployed at ${deployed.settlement.mockUSDC}`);
  }
  console.log(`✓ MockUSDC deployed at ${deployed.settlement.mockUSDC}`);

  const mockDexCode = await settlementProvider.getCode(deployed.settlement.mockDEX);
  if (mockDexCode === "0x") {
    throw new Error(`MockDEX not deployed at ${deployed.settlement.mockDEX}`);
  }
  console.log(`✓ MockDEX deployed at ${deployed.settlement.mockDEX}`);

  console.log("\n✓ All L1s reachable and contracts verified at deployed addresses.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
