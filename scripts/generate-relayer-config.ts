import "dotenv/config";
import { ethers } from "ethers";
import * as fs from "fs";

/**
 * Generate icm-relayer-config.json from deployed.json and .env.
 *
 * This avoids hard-coding local-network subnet/blockchain IDs and relayer keys
 * in the repo. Run it after `npm run deploy:local`.
 */

const P_CHAIN_URL = process.env.P_CHAIN_URL || "http://127.0.0.1:9650";

function extractBlockchainIdFromRpc(rpcUrl: string): string {
  // RPC URLs look like http://host:port/ext/bc/<cb58-blockchain-id>/rpc
  const match = rpcUrl.match(/\/ext\/bc\/([^/]+)\/rpc$/);
  if (!match) {
    throw new Error(`Cannot parse blockchain ID from RPC URL: ${rpcUrl}`);
  }
  return match[1];
}

async function pChainCall(method: string, params: any = {}): Promise<any> {
  const res = await fetch(P_CHAIN_URL + "/ext/bc/P", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  const json = await res.json();
  if (json.error) {
    throw new Error(`P-Chain ${method} failed: ${JSON.stringify(json.error)}`);
  }
  return json.result;
}

async function getSubnetId(blockchainIdCb58: string): Promise<string> {
  const result = await pChainCall("platform.getBlockchains", {});
  const bc = result.blockchains.find((b: any) => b.id === blockchainIdCb58);
  if (!bc) {
    throw new Error(`Subnet ID for blockchain ${blockchainIdCb58} not found on P-Chain`);
  }
  return bc.subnetID;
}

async function main() {
  if (!fs.existsSync("deployed.json")) {
    throw new Error("deployed.json not found. Run deploy:local first.");
  }

  const deployed = JSON.parse(fs.readFileSync("deployed.json", "utf8"));

  const initiatorBlockchainId = extractBlockchainIdFromRpc(deployed.initiator.rpcUrl);
  const settlementBlockchainId = extractBlockchainIdFromRpc(deployed.settlement.rpcUrl);

  const initiatorSubnetId = await getSubnetId(initiatorBlockchainId);
  const settlementSubnetId = await getSubnetId(settlementBlockchainId);

  const relayerKey = process.env.RELAYER_PRIVATE_KEY;
  if (!relayerKey) {
    throw new Error(
      "RELAYER_PRIVATE_KEY is required. Set it in .env before generating the relayer config."
    );
  }

  const relayerAddress = new ethers.Wallet(relayerKey).address;

  const config = {
    "log-level": "info",
    "storage-location": "./.icm-relayer-storage",
    "allow-private-ips": true,
    "p-chain-api": {
      "base-url": P_CHAIN_URL,
    },
    "info-api": {
      "base-url": P_CHAIN_URL,
    },
    "source-blockchains": [
      {
        "subnet-id": initiatorSubnetId,
        "blockchain-id": initiatorBlockchainId,
        vm: "evm",
        "rpc-endpoint": {
          "base-url": deployed.initiator.rpcUrl,
        },
        "ws-endpoint": {
          "base-url": deployed.initiator.rpcUrl.replace("/rpc", "/ws").replace("http:", "ws:"),
        },
        "message-contracts": {
          [deployed.initiator.teleporterMessenger]: {
            "message-format": "teleporter",
            settings: {
              "reward-address": relayerAddress,
            },
          },
        },
        "supported-destinations": [
          {
            "blockchain-id": settlementBlockchainId,
          },
        ],
      },
    ],
    "destination-blockchains": [
      {
        "subnet-id": settlementSubnetId,
        "blockchain-id": settlementBlockchainId,
        vm: "evm",
        "rpc-endpoint": {
          "base-url": deployed.settlement.rpcUrl,
        },
        "account-private-key": relayerKey.replace(/^0x/, ""),
      },
    ],
  };

  fs.writeFileSync("icm-relayer-config.json", JSON.stringify(config, null, 2));
  console.log("Wrote icm-relayer-config.json");
  console.log("  Relayer address:", relayerAddress);
  console.log("  Initiator subnet:", initiatorSubnetId);
  console.log("  Settlement subnet:", settlementSubnetId);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
