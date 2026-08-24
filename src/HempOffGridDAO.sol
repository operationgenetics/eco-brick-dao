// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract HempOffGridDAO {
    uint256 public constant THRESHOLD_DAI = 5_000_000_000 * 1e18;
    address public constant OBS_TOKEN_ADDRESS = 0x2D8760e2877148d239a54952A458710553B2B54b;
    address public constant DESIGNATED_UPDATE_WALLET = 0xaF570ce3b32D765b1236635B0f541a7487A1fB8e;
    address public constant ARBITRUM_DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    string public constant HEMP_SPECIFICATION = "GMO hemp, all natural hemp color, no added colors";
    string public constant PRODUCT_SCOPE = "Clothing, hemp toilet paper and wipes";
    string public constant NONPROFIT_MISSION = "Strictly for free public giveaway and nonprofit use only";

    string public pqcAlgorithmSuite = "Hybrid CRYSTALS-Dilithium + Ed25519 (MCU Biometric Bound)";
    address public updateWallet;
    address public roomieBot;
    bool public isImmutable = false;

    uint256 public constant SPENDING_COOLDOWN = 60 days;
    uint256 public lastFundReleaseTimestamp;

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

    mapping(address => bytes32) public roomieBotQuantumKeyHashes;

    event RoomieBotUpdated(address indexed newRoomieBot);
    event QuantumKeyRegistered(address indexed botOrNode, bytes32 keyHash);
    event ProposalCreated(uint256 indexed proposalId, string description, address recipient, uint256 amount);
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event PermissionsRevoked(address indexed updateWallet);
    event MonthlyLPIssued(address indexed member, uint256 amount, uint256 monthIdentifier);
    event ObsVaulted(address indexed account, uint256 amount);
    event ObsWithdrawnFromVault(address indexed account, uint256 amount);

    modifier onlyUpdateWallet() {
        require(msg.sender == updateWallet && msg.sender == DESIGNATED_UPDATE_WALLET, "Unauthorized: Only designated update wallet");
        require(!isImmutable, "Contract state is immutable");
        _;
    }

    modifier fundsUnlocked() {
        require(IERC20(ARBITRUM_DAI).balanceOf(OBS_TOKEN_ADDRESS) >= THRESHOLD_DAI, "Treasury locked: 5B DAI bonding curve threshold not met");
        _;
    }

    constructor() {
        updateWallet = DESIGNATED_UPDATE_WALLET;
        roomieBot = DESIGNATED_UPDATE_WALLET;
        lastFundReleaseTimestamp = block.timestamp > SPENDING_COOLDOWN ? block.timestamp - SPENDING_COOLDOWN : 0;
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
        bool success = IERC20(OBS_TOKEN_ADDRESS).transferFrom(msg.sender, address(this), amount);
        require(success, "OBS transfer to vault failed");
        obsVaultBalances[msg.sender] += amount;
        totalObsVaulted += amount;
        emit ObsVaulted(msg.sender, amount);
    }

    function withdrawObsFromVault(uint256 amount) external fundsUnlocked {
        require(obsVaultBalances[msg.sender] >= amount, "Insufficient vaulted OBS balance");
        obsVaultBalances[msg.sender] -= amount;
        totalObsVaulted -= amount;
        bool success = IERC20(OBS_TOKEN_ADDRESS).transfer(msg.sender, amount);
        require(success, "OBS withdrawal transfer failed");
        emit ObsWithdrawnFromVault(msg.sender, amount);
    }

    function createProposal(string memory description, address payable recipient, uint256 amount, uint256 durationDays) external returns (uint256) {
        require(getEffectiveLPBalance(msg.sender) >= 50 * 1e18, "Insufficient active LP tokens: 50 LP required to propose");
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
        require(block.timestamp < proposal.deadline, "Voting period has ended");
        require(!proposal.executed, "Proposal already executed");
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        uint256 weight = getEffectiveLPBalance(msg.sender); // 1:1 LP tokens to votes ratio
        require(weight > 0, "No active voting weight");
        hasVoted[proposalId][msg.sender] = true;
        if (support) { proposal.yesVotes += weight; } else { proposal.noVotes += weight; }
        emit Voted(proposalId, msg.sender, support, weight);
    }

    function executeProposal(uint256 proposalId) external fundsUnlocked {
        require(block.timestamp >= lastFundReleaseTimestamp + SPENDING_COOLDOWN, "Robot timeout active: Once every 2 months");
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.deadline, "Voting still active");
        require(!proposal.executed, "Proposal already executed");
        require(proposal.yesVotes > proposal.noVotes, "Proposal failed majority vote");
        proposal.executed = true;
        lastFundReleaseTimestamp = block.timestamp;
        bool success = IERC20(ARBITRUM_DAI).transfer(proposal.recipient, proposal.amount);
        require(success, "DAI transfer failed");
        emit ProposalExecuted(proposalId);
    }

    function setupRoomieRobotAndLock(address botOrNode, bytes32 pqcKeyHash) external onlyUpdateWallet {
        roomieBot = botOrNode;
        roomieBotQuantumKeyHashes[botOrNode] = pqcKeyHash;
        emit RoomieBotUpdated(botOrNode);
        emit QuantumKeyRegistered(botOrNode, pqcKeyHash);
    }

    function revokeAndUpdatePermissions() external onlyUpdateWallet {
        isImmutable = true;
        updateWallet = address(0);
        emit PermissionsRevoked(msg.sender);
    }

    receive() external payable {}
}
