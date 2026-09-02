#!/usr/bin/env node
/**
 * Off-Grid DAO WalletConnect Deployer — No config besides file path + MM signing.
 * Usage:
 *   node deploy.js                          // deploys EcoBrickDAO to Arbitrum One via WalletConnect QR
 *   node deploy.js src/EcoBrickDAO.sol      // explicit file path
 *   node deploy.js src/HempOffGridDAO.sol
 *   RPC_URL env or defaults to Arbitrum One public RPC.
 *
 * Requirements: only correct file path + signing with MetaMask WalletConnect.
 * No private keys, no constructor args — all rules hardcoded (OBS token, 5B DAI threshold, wallet 0xaF57..., hybrid PQC, 100 LP/50 proposal/1:1 vote, 60-day robot gate, patent placeholder).
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import qrcode from "qrcode-terminal";
import { ethers } from "ethers";
import { EthereumProvider } from "@walletconnect/ethereum-provider";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Hardcoded canonical addresses — mirrors on-chain constants
const OBS_TOKEN = "0x2D8760e2877148d239a54952A458710553B2B54b";
const UPDATE_WALLET = "0xaF570ce3b32D765b1236635B0f541a7487A1fB8e";
const ARBITRUM_DAI = "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1";

const ARBITRUM_CHAIN_ID = 42161;
const DEFAULT_RPC = process.env.RPC_URL || process.env.ARBITRUM_RPC || "https://arb1.arbitrum.io/rpc";

const TARGET_MAP = {
  "EcoBrickDAO": "out/EcoBrickDAO.sol/EcoBrickDAO.json",
  "HempOffGridDAO": "out/HempOffGridDAO.sol/HempOffGridDAO.json",
  "src/EcoBrickDAO.sol": "out/EcoBrickDAO.sol/EcoBrickDAO.json",
  "src/HempOffGridDAO.sol": "out/HempOffGridDAO.sol/HempOffGridDAO.json",
};

async function main() {
  const arg = process.argv[2] || "src/EcoBrickDAO.sol";
  const artifactRel = TARGET_MAP[arg] || TARGET_MAP[path.basename(arg, ".sol")] || "out/EcoBrickDAO.sol/EcoBrickDAO.json";
  const artifactPath = path.join(__dirname, artifactRel);

  if (!fs.existsSync(artifactPath)) {
    console.error(`\n[!] Artifact not found: ${artifactPath}`);
    console.error(`    Run: forge build`);
    console.error(`    Then: node deploy.js ${arg}\n`);
    process.exit(1);
  }

  const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
  const abi = artifact.abi;
  const bytecode = artifact.bytecode.object || artifact.bytecode;
  if (!bytecode || bytecode === "0x") {
    console.error("[!] Bytecode empty — did forge build succeed?");
    process.exit(1);
  }

  console.log("\n=== Off-Grid DAO Deployer (Arbitrum One) ===");
  console.log(`Contract: ${arg}`);
  console.log(`OBS Token: ${OBS_TOKEN}`);
  console.log(`Update Wallet: ${UPDATE_WALLET} (only wallet can call setupRoomieRobotAndLock / updatePatentInfo / revoke)`);
  console.log(`Bonding Threshold: 5,000,000,000 DAI (DAI @ ${ARBITRUM_DAI} balance of OBS token)`);
  console.log(`LP: 100/month expire EOM, 50/proposal, 1:1 vote | Robot: 60-day bimonthly MCU auth | Vault: OBS | PQC: Hybrid Dilithium/Falcon + ECDSA secp256k1`);
  console.log(`RPC: ${DEFAULT_RPC}`);
  console.log(`Chain: Arbitrum One (${ARBITRUM_CHAIN_ID})`);
  console.log(`Hybrid PQC: ECDSA secp256k1 (native) + ML-DSA/Falcon-512 (MCU) — biometric hard-locked on Roomie MCU, only pubkey on-chain`);
  console.log(`Off-Grid: Fully off-grid manufacturing until all waste recycled`);
  console.log("\n[i] Nothing else needed — just scan QR with MetaMask (WalletConnect) and sign.\n");

  // WalletConnect — replace with your WalletConnect projectId via env WALLETCONNECT_PROJECT_ID or use demo
  const projectId = process.env.WALLETCONNECT_PROJECT_ID || "c4f79cc821944d9680842e34466bea123"; // demo; set your own for prod
  let provider;
  try {
    provider = await EthereumProvider.init({
      projectId,
      chains: [ARBITRUM_CHAIN_ID],
      showQrModal: false,
      rpcMap: { [ARBITRUM_CHAIN_ID]: DEFAULT_RPC },
      metadata: {
        name: "Eco-Brick DAO Deployer",
        description: "Off-Grid Eco-Brick/Recycled Glass DAO — Hybrid PQC + Roomie Robot",
        url: "https://ecobrick-dao.local",
        icons: ["https://avatars.githubusercontent.com/u/37784886"],
      },
    });
  } catch (e) {
    console.error("[!] WalletConnect init failed. Set WALLETCONNECT_PROJECT_ID env or check network.", e.message);
    process.exit(1);
  }

  provider.on("display_uri", (uri) => {
    console.log("\n[QR] Scan with MetaMask -> WalletConnect -> Scan QR:\n");
    qrcode.generate(uri, { small: true });
    console.log(`\nURI: ${uri}\n`);
    console.log("Waiting for wallet approval...\n");
  });

  await provider.connect();
  console.log("[✓] WalletConnect connected");

  const ethersProvider = new ethers.BrowserProvider(provider);
  const signer = await ethersProvider.getSigner();
  const address = await signer.getAddress();
  console.log(`[✓] Signer: ${address}`);

  if (address.toLowerCase() !== UPDATE_WALLET.toLowerCase()) {
    console.warn(`\n[!] Signer is not the designated update wallet (${UPDATE_WALLET}).`);
    console.warn(`    Deployment still succeeds, but only ${UPDATE_WALLET} can later call setupRoomieRobotAndLock / updatePatentInfo / revokeAndUpdatePermissions.`);
    console.warn(`    Ensure you later connect with ${UPDATE_WALLET} to configure Roomie robot.\n`);
  } else {
    console.log(`[✓] Signer matches designated update wallet — will be able to call setupRoomieRobotAndLock immediately.\n`);
  }

  const network = await ethersProvider.getNetwork();
  if (Number(network.chainId) !== ARBITRUM_CHAIN_ID) {
    console.warn(`[!] Wallet is on chain ${network.chainId}, expected ${ARBITRUM_CHAIN_ID} (Arbitrum One). Please switch in MetaMask.`);
  }

  const factory = new ethers.ContractFactory(abi, bytecode, signer);
  console.log(`[i] Deploying ${path.basename(arg)} — no constructor args (all params hardcoded)...`);
  const contract = await factory.deploy();
  console.log(`[i] Tx sent: ${contract.deploymentTransaction()?.hash}`);
  console.log(`[i] Waiting for confirmation...`);
  await contract.waitForDeployment();
  const deployedAt = await contract.getAddress();
  console.log(`\n[✓] Deployed at: ${deployedAt}`);
  console.log(`[✓] Tx hash: ${contract.deploymentTransaction()?.hash}`);
  console.log(`\nNext steps (with ${UPDATE_WALLET}):`);
  console.log(`  1) setupRoomieRobotAndLock(roomieBotAddr, pqcPubKeyBytes) — callable immediately, updatable when MCU hardware arrives`);
  console.log(`  2) updatePatentInfo("Eco-Brick Model Name", "US-PATENT-XXXX") — when patent granted`);
  console.log(`  3) after hardware finalization: revokeAndUpdatePermissions() — makes contract immutable (updateWallet -> 0)`);
  console.log(`  4) Robots enforce 60-day bimonthly spending via checkAndAuthorizeBimonthlySpending(mcuSignature) before any vault withdraw.\n`);
  console.log(`Verify on Arbiscan: https://arbiscan.io/address/${deployedAt}\n`);

  await provider.disconnect().catch(()=>{});
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
