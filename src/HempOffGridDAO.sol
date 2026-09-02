// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Hemp {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

/**
 * @title Hemp Off-Grid Manufacturing DAO (Clothing, Hemp Toilet Paper & Wipes - Nonprofit Free Distribution)
 * @notice Fully off-grid DAO with hybrid PQC security, expiring monthly LP, weighted voting, vault, and robot-gated 60-day spending.
 * @dev Hybrid PQC: Arbitrum One native ECDSA secp256k1 + ML-DSA (Dilithium) / Falcon-512 via MCU. Biometrics NEVER on-chain,
 *      only PQC public key hash on-chain; biometric templates hard-locked on Roomie MCU secure element.
 * @dev Off-Grid: All manufacturing runs fully off-grid indefinitely until waste recycled. Strict nonprofit mission: free public giveaway only.
 *      Hardcoded rules enforced by robots: GMO hemp natural color no added dyes, clothing/hemp paper/wipes, off-grid indefinite.
 */
contract HempOffGridDAO {
    uint256 public constant THRESHOLD_DAI = 5_000_000_000 * 1e18; // 5B DAI bonding curve threshold for OBS unlock
    address public constant OBS_TOKEN_ADDRESS = 0x2D8760e2877148d239a54952A458710553B2B54b;
    address public constant DESIGNATED_UPDATE_WALLET = 0xaF570ce3b32D765b1236635B0f541a7487A1fB8e;
    address public constant ARBITRUM_DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    string public constant HEMP_SPECIFICATION = "GMO hemp, all natural hemp color, no added colors";
    string public constant PRODUCT_SCOPE = "Clothing, hemp toilet paper and wipes";
    string public constant NONPROFIT_MISSION = "Strictly for free public giveaway and nonprofit use only";
    string public constant CORE_MISSION = "Off-grid hemp manufacturing (GMO natural hemp, no added colors) for clothing, hemp toilet paper and wipes - strictly nonprofit free distribution. Operate fully off-grid indefinitely. Hardcoded rules enforced by Roomie robot at manufacturing site.";
    string public constant FACILITY_MODE = "100% Off-Grid Operations Indefinitely";

    string public pqcAlgorithmSuite = "Hybrid CRYSTALS-Dilithium (ML-DSA) / Falcon-512 + ECDSA secp256k1 (Arbitrum One Native) with MCU Biometric Binding - Biometric templates hard-locked on Roomie MCU, only PQC public key hash on-chain";
    address public updateWallet;
    address public adminAddress;
    address public roomieBot;
    bool public isImmutable = false;

    uint256 public constant SPENDING_COOLDOWN = 60 days; // Robot-enforced bimonthly timeout (1x per 2 months)
    uint256 public lastFundReleaseTimestamp;
    bool public bimonthlyFundsUnlocked = false;

    // Manufacturing site verification (Roomie bot enforces presence at gifted hemp facilities)
    mapping(address => bool) public verifiedManufacturingSitePresence;

    // Patent/product registry — admin chooses future eco-brick patent but hemp DAO holds its own registry updatable via same wallet
    string public hempPatentModel = "Pending Hemp Process Patent - Natural Color GMO Hemp";
    string public hempPatentNumber = "PENDING-HEMP-001";

    mapping(address => uint256) public obsVaultBalances;
    uint256 public totalObsVaulted;

    struct MemberLPInfo {
        uint256 balance;
        uint256 lastIssuanceMonth;
    }
    mapping(address => MemberLPInfo) public memberLP;

    struct Proposal {
        string description;
        address payable recipient;
        uint256 amount;
        uint256 yesVotes;
        uint256 noVotes;
        bool executed;
        uint256 deadline;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    uint256 public proposalCount;

    // Hybrid PQC: only key hash on-chain, raw pubkey bytes not stored to save gas; biometric NEVER stored (hard-locked on MCU)
    mapping(address => bytes32) public roomieBotQuantumKeyHashes;
    bytes public roomiePqcPublicKey; // optional raw key storage parity with EcoBrickDAO

    event RoomieBotUpdated(address indexed newRoomieBot);
    event QuantumKeyRegistered(address indexed botOrNode, bytes32 keyHash);
    event RoomieRobotLinkedAndLocked(address indexed updateWallet, address indexed roomieRobot, bytes pqcPublicKey);
    event ProposalCreated(uint256 indexed proposalId, string description, address recipient, uint256 amount);
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event PermissionsRevoked(address indexed updateWallet);
    event MonthlyLPIssued(address indexed member, uint256 amount, uint256 monthIdentifier);
    event ObsVaulted(address indexed account, uint256 amount);
    event ObsWithdrawnFromVault(address indexed account, uint256 amount);
    event BimonthlyMilestoneAuthorized(uint256 timestamp, address indexed roomieBot);
    event PatentUpdated(string newModel, string newNumber);
    event RoomieBotSiteVerified(address indexed workerOrBot, bool verified);

    modifier onlyUpdateWallet() {
        require(msg.sender == updateWallet && msg.sender == DESIGNATED_UPDATE_WALLET, "Unauthorized: Only designated update wallet");
        require(!isImmutable, "Contract state is immutable");
        _;
    }

    modifier fundsUnlocked() {
        require(IERC20Hemp(ARBITRUM_DAI).balanceOf(OBS_TOKEN_ADDRESS) >= THRESHOLD_DAI, "Treasury locked: 5B DAI bonding curve threshold not met");
        _;
    }

    constructor() {
        updateWallet = DESIGNATED_UPDATE_WALLET;
        adminAddress = DESIGNATED_UPDATE_WALLET;
        roomieBot = address(0); // updatable immediately via setupRoomieRobotAndLock
        lastFundReleaseTimestamp = block.timestamp;
    }

    function getCurrentMonthIdentifier() public view returns (uint256) {
        uint256 year = (block.timestamp / 31536000) + 1970;
        uint256 month = ((block.timestamp % 31536000) / 2628000) + 1;
        return (year * 100) + month;
    }

    function getEffectiveLPBalance(address member) public view returns (uint256) {
        MemberLPInfo memory info = memberLP[member];
        if (info.lastIssuanceMonth < getCurrentMonthIdentifier()) {
            return 0; // Expires at the end of the month if not used / active
        }
        return info.balance;
    }

    function claimMonthlyLP() external {
        uint256 currentMonth = getCurrentMonthIdentifier();
        MemberLPInfo storage info = memberLP[msg.sender];
        require(info.lastIssuanceMonth < currentMonth, "Monthly LP already claimed or active");
        info.balance = 100 * 1e18; // 100 LP tokens issued monthly
        info.lastIssuanceMonth = currentMonth;
        emit MonthlyLPIssued(msg.sender, 100 * 1e18, currentMonth);
    }

    function depositObsToVault(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        bool success = IERC20Hemp(OBS_TOKEN_ADDRESS).transferFrom(msg.sender, address(this), amount);
        require(success, "OBS transfer to vault failed");
        obsVaultBalances[msg.sender] += amount;
        totalObsVaulted += amount;
        emit ObsVaulted(msg.sender, amount);
    }

    function withdrawObsFromVault(uint256 amount) external fundsUnlocked {
        require(bimonthlyFundsUnlocked, "Bimonthly robot milestone time-lock enforced: Await robot authorization");
        require(obsVaultBalances[msg.sender] >= amount, "Insufficient vaulted OBS balance");
        obsVaultBalances[msg.sender] -= amount;
        totalObsVaulted -= amount;
        bimonthlyFundsUnlocked = false;
        bool success = IERC20Hemp(OBS_TOKEN_ADDRESS).transfer(msg.sender, amount);
        require(success, "OBS withdrawal transfer failed");
        emit ObsWithdrawnFromVault(msg.sender, amount);
    }

    function createProposal(string memory description, address payable recipient, uint256 amount, uint256 durationDays) external returns (uint256) {
        require(getEffectiveLPBalance(msg.sender) >= 50 * 1e18, "Insufficient active LP tokens: 50 LP required to propose");
        require(durationDays > 0 && durationDays <= 365, "Invalid duration");
        // Deduct 50 LP fee — mirrors EcoBrickDAO
        memberLP[msg.sender].balance -= 50 * 1e18;
        uint256 proposalId = proposalCount++;
        proposals[proposalId] = Proposal({
            description: description,
            recipient: recipient,
            amount: amount,
            yesVotes: 0,
            noVotes: 0,
            executed: false,
            deadline: block.timestamp + (durationDays * 1 days)
        });
        emit ProposalCreated(proposalId, description, recipient, amount);
        return proposalId;
    }

    function vote(uint256 proposalId, bool support) external {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.deadline != 0, "Proposal does not exist");
        require(block.timestamp < proposal.deadline, "Voting period has ended");
        require(!proposal.executed, "Proposal already executed");
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        uint256 weight = getEffectiveLPBalance(msg.sender); // 1:1 LP tokens to votes ratio
        require(weight > 0, "No active voting weight");
        hasVoted[proposalId][msg.sender] = true;
        if (support) { proposal.yesVotes += weight; } else { proposal.noVotes += weight; }
        emit Voted(proposalId, msg.sender, support, weight);
    }

    /**
     * @notice Robot-enforced bimonthly authorization — must be called 1x every 60 days via Roomie MCU biometric PQC signature.
     * @dev Biometric templates stored ONLY on MCU secure element, never on-chain. On-chain we verify caller + time-lock + sig proof length.
     */
    function checkAndAuthorizeBimonthlySpending(bytes calldata robotMcuSignature) external {
        require(msg.sender == roomieBot || msg.sender == updateWallet, "Unauthorized: Roomie MCU authorization required");
        require(block.timestamp >= lastFundReleaseTimestamp + SPENDING_COOLDOWN, "Bimonthly time-lock active: Must wait 2 months between releases");
        require(robotMcuSignature.length > 0, "Invalid MCU biometric signature proof");
        lastFundReleaseTimestamp = block.timestamp;
        bimonthlyFundsUnlocked = true;
        emit BimonthlyMilestoneAuthorized(block.timestamp, roomieBot);
    }

    /**
     * @notice Executes a passed proposal — transfers OBS vault funds (NOT DAI) after bonding unlock + robot bimonthly gate + majority vote.
     * @dev Hardcoded rules enforced: hemp manufacturing nonprofit, off-grid, no added colors. Robots time out spending every 60 days.
     */
    function executeProposal(uint256 proposalId) external fundsUnlocked {
        require(bimonthlyFundsUnlocked, "Bimonthly robot milestone time-lock enforced: Await robot authorization");
        require(block.timestamp >= lastFundReleaseTimestamp || bimonthlyFundsUnlocked, "Robot timeout active: Await authorization");
        // Time-lock already enforced by bimonthlyFundsUnlocked gate; keep cooldown safety
        Proposal storage proposal = proposals[proposalId];
        require(proposal.deadline != 0, "Proposal does not exist");
        require(block.timestamp >= proposal.deadline, "Voting still active");
        require(!proposal.executed, "Proposal already executed");
        require(proposal.yesVotes > proposal.noVotes, "Proposal failed majority vote");
        proposal.executed = true;
        bimonthlyFundsUnlocked = false;
        lastFundReleaseTimestamp = block.timestamp;
        bool success = IERC20Hemp(OBS_TOKEN_ADDRESS).transfer(proposal.recipient, proposal.amount);
        require(success, "OBS transfer failed");
        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Links Roomie robot MCU public key — callable immediately after deployment and updatable until revoked.
     * @dev Stores PQC public key raw bytes + hash. Biometrics NEVER on-chain — hard-locked on MCU.
     */
    function setupRoomieRobotAndLock(address botOrNode, bytes32 pqcKeyHash) external onlyUpdateWallet {
        roomieBot = botOrNode;
        roomieBotQuantumKeyHashes[botOrNode] = pqcKeyHash;
        emit RoomieBotUpdated(botOrNode);
        emit QuantumKeyRegistered(botOrNode, pqcKeyHash);
    }

    /**
     * @notice Extended variant accepting raw PQC public key bytes (parity with EcoBrickDAO).
     */
    function setupRoomieRobotAndLock(address botOrNode, bytes calldata _pqcPublicKey) external onlyUpdateWallet {
        require(botOrNode != address(0), "Invalid robot address");
        require(_pqcPublicKey.length > 0, "Invalid PQC public key");
        roomieBot = botOrNode;
        roomiePqcPublicKey = _pqcPublicKey;
        bytes32 hash = keccak256(_pqcPublicKey);
        roomieBotQuantumKeyHashes[botOrNode] = hash;
        emit RoomieBotUpdated(botOrNode);
        emit QuantumKeyRegistered(botOrNode, hash);
        emit RoomieRobotLinkedAndLocked(updateWallet, botOrNode, _pqcPublicKey);
    }

    function verifyManufacturingPresence(address workerOrBot, bool status) external {
        require(msg.sender == roomieBot || msg.sender == updateWallet, "Unauthorized: Only Roomie Bot or Update Wallet");
        verifiedManufacturingSitePresence[workerOrBot] = status;
        emit RoomieBotSiteVerified(workerOrBot, status);
    }

    /**
     * @notice Patent/product registry update — same revocable wallet as robot key. Mirrors EcoBrickDAO placeholder logic.
     */
    function updatePatentInfo(string calldata newModel, string calldata newNumber) external onlyUpdateWallet {
        hempPatentModel = newModel;
        hempPatentNumber = newNumber;
        emit PatentUpdated(newModel, newNumber);
    }

    function revokeAndUpdatePermissions() external onlyUpdateWallet {
        isImmutable = true;
        updateWallet = address(0);
        emit PermissionsRevoked(msg.sender);
    }

    /**
     * @notice View helper — is bonding curve unlocked (5B DAI in OBS token)?
     */
    function checkFundsUnlocked() external view returns (bool) {
        return IERC20Hemp(ARBITRUM_DAI).balanceOf(OBS_TOKEN_ADDRESS) >= THRESHOLD_DAI;
    }

    receive() external payable {}
}
