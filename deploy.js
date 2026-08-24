const { ethers } = require("ethers");
const { EthereumProvider } = require("@walletconnect/ethereum-provider");
const QRCode = require("qrcode-terminal");
const fs = require("fs");
const path = require("path");

const contractArtifactPath = path.join(__dirname, "out/HempOffGridDAO.sol/HempOffGridDAO.json");
if (!fs.existsSync(contractArtifactPath)) {
    console.error("Error: Contract artifact not found. Please run 'forge build' first.");
    process.exit(1);
}
const contractArtifact = JSON.parse(fs.readFileSync(contractArtifactPath, "utf8"));

async function main() {
    console.log("Initializing WalletConnect session for Arbitrum One (Chain ID: 42161)...");

    const wcProvider = await EthereumProvider.init({
        projectId: "3a8170812b534d0ff9d794f19a901d64",
        chainId: 42161,
        chains: [42161],
        rpcMap: {
            42161: "https://arb1.arbitrum.io/rpc"
        },
        metadata: {
            name: "Hemp Off-Grid DAO Deployment",
            description: "Off-Grid PQC DAO Deployment on Arbitrum One",
            url: "https://obscura.network",
            icons: ["https://avatars.githubusercontent.com/u/37784886"]
        },
        showQrModal: false
    });

    wcProvider.on("display_uri", (uri) => {
        console.log("\n==================================================================");
        console.log("SCAN THIS QR CODE IN METAMASK MOBILE (Ensure network is Arbitrum One)");
        console.log("==================================================================\n");
        QRCode.generate(uri, { small: true }, (qr) => {
            console.log(qr);
        });
        console.log(`\nDirect WalletConnect URI Link:\n${uri}\n`);
    });

    console.log("Connecting to WalletConnect relay network...");
    await wcProvider.connect();

    const provider = new ethers.BrowserProvider(wcProvider, 42161);
    const signer = await provider.getSigner();
    const deployerAddress = await signer.getAddress();

    console.log(`\nSuccessfully Connected Wallet: ${deployerAddress}`);

    const factory = new ethers.ContractFactory(
        contractArtifact.abi,
        contractArtifact.bytecode.object,
        signer
    );

    console.log("Deploying HempOffGridDAO to Arbitrum One... Please approve in MetaMask mobile.");

    const contract = await factory.deploy({
        gasLimit: 3500000
    });

    const txResponse = contract.deploymentTransaction();
    console.log(`Transaction Broadcasted! Hash: ${txResponse.hash}`);
    console.log("Waiting for block confirmation on Arbitrum One...");

    await contract.waitForDeployment();
    const contractAddress = await contract.getAddress();

    console.log(`\n==========================================`);
    console.log(`Deployment Successful on Arbitrum One!`);
    console.log(`HempOffGridDAO Address: ${contractAddress}`);
    console.log(`==========================================\n`);

    await wcProvider.disconnect();
    process.exit(0);
}

main().catch((error) => {
    console.error("\nDeployment failed:", error);
    process.exit(1);
});
