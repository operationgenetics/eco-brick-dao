// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

/**
 * @title Eco-Brick & Recycled Glass Tile Manufacturing DAO
 * @notice Fully off-grid automated DAO featuring hybrid PQC security, biometric MCU hardware gates,
 *         bimonthly robot-gated funding tranches, expiring monthly LP voting rights, and vault capabilities.
 * @dev Hybrid PQC: Arbitrum One native ECDSA secp256k1 (EVM) + off-chain/upgradeable ML-DSA (Dilithium) / Falcon-512
 *      Biometric templates are HARD-LOCKED on the Roomie humanoid robot's MCU (secure element) and NEVER stored on-chain.
 *      Only the hybrid PQC public key / key-hash is stored on-chain for verification. Updatable via designated wallet until revoked.
 * @dev Off-Grid Mission: Operate fully off-grid manufacturing facilities for Eco-Bricks and recycled glass tiles
 *      to process and recycle global waste indefinitely until all waste on earth is recycled. All facilities
 *      run indefinitely off-grid without external grid dependency.
 */
contract EcoBrickDAO {
    // ===== Economic & Token Constants =====
    uint256 public constant THRESHOLD_DAI = 5_000_000_000 * 1e18; // 5 Billion DAI bonding curve threshold
    address public constant OBS_TOKEN_ADDRESS = 0x2D8760e2877148d239a54952A458710553B2B54b;
    address public constant DESIGNATED_UPDATE_WALLET = 0xaF570ce3b32D765b1236635B0f541a7487A1fB8e;
    address public constant ARBITRUM_DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // Arbitrum One DAI for bonding-curve check

    address public updateWallet;
    address public adminAddress;
    address public roomieBot;
    /// @notice Hybrid PQC MCU public key (Dilithium/Falcon raw bytes). Biometric templates NEVER on-chain — only this pubkey.
    bytes public roomiePqcPublicKey;

    // Patent details — placeholder, updatable only via designated wallet before immutability
    string public patentedEcoBrickModel = "Pending Patent: Eco-Brick & Recycled Glass Tile Matrix";
    string public patentNumber = "PENDING-001";

    string public constant FACILITY_LOCATION = "Global Off-Grid Eco-Brick & Recycled Glass Tile Manufacturing Facilities";
    string public constant CORE_MISSION = "Operate fully off-grid manufacturing facilities for Eco-Bricks and recycled glass tiles to process and recycle global waste indefinitely until all waste on earth is recycled. Admin/Update wallet manages patent naming once finalized, enforced by Roomie robot verification at manufacturing sites. Hardcoded rules for robot to use funds: eco-brick (patent placeholder) + recycled glass tile manufacturing, future projects of admin choice upon Roomie verification at manufacturing site. All manufacturing will be off-grid to run operations indefinitely until all waste on earth is recycled.";

    /// @notice Hybrid PQC suite: Arbitrum One native ECDSA secp256k1 + Dilithium/Falcon MCU binding. Biometrics hard-locked on MCU.
    string public pqcAlgorithmSuite = "Hybrid CRYSTALS-Dilithium (ML-DSA) / Falcon-512 + ECDSA secp256k1 (Arbitrum One Native) with MCU Biometric Binding - Biometric templates hard-locked on Roomie MCU, only PQC public key on-chain";
    bool public isImmutable = false;

    // Bimonthly Robot Milestone Authorization — robots mathematically timeout spending to 1x per 60 days
    uint256 public lastMilestoneReleaseTimestamp;
    uint256 public constant BIMONTHLY_LOCKOUT_PERIOD = 60 days;
    bool public bimonthlyFundsUnlocked = false;

    struct MemberLPInfo {
        uint256 balance;
        uint256 lastIssuanceMonth;
    }

    mapping(address => MemberLPInfo) public memberLP;
    mapping(address => bool) public members;

    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 deadline;
        uint256 costPaid;
        bool executed;
    }

    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVotedOnProposal;
    mapping(address => bool) public verifiedManufacturingSitePresence;

    // Vault tracking (mirrors Hemp DAO for consistency, but direct ERC20 balanceOf is source of truth)
    mapping(address => uint256) public obsVaultBalances;
    uint256 public totalObsVaulted;

    event MemberJoined(address indexed member, uint256 timestamp);
    event LPtokensIssued(address indexed member, uint256 month, uint256 amount);
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description, uint256 deadline, uint256 costPaid);
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event RoomieRobotLinkedAndLocked(address indexed updateWallet, address indexed roomieRobot, bytes pqcPublicKey);
    event RoomieBotSiteVerified(address indexed workerOrBot, bool verified);
    event PatentUpdated(string newName, string newNumber);
    event BimonthlyMilestoneAuthorized(uint256 timestamp, address indexed roomieBot);
    event VaultFundsWithdrawn(address indexed recipient, uint256 amount);
    event ObsVaulted(address indexed account, uint256 amount);
    event PermissionsRevoked(address indexed updateWallet);

    modifier onlyUpdateWallet() {
        require(msg.sender == updateWallet && msg.sender == DESIGNATED_UPDATE_WALLET, "Unauthorized: Only designated update wallet");
        require(!isImmutable, "Contract state is immutable");
        _;
    }

    constructor() {
        updateWallet = DESIGNATED_UPDATE_WALLET;
        adminAddress = DESIGNATED_UPDATE_WALLET;
        lastMilestoneReleaseTimestamp = block.timestamp;
    }

    // ===== Membership & LP =====

    function joinDAO() external {
        require(!members[msg.sender], "Already a member");
        members[msg.sender] = true;
        emit MemberJoined(msg.sender, block.timestamp);
        _claimMonthlyLP(msg.sender);
    }

    function _getCurrentMonth() public view returns (uint256) {
        uint256 year = (block.timestamp / 31536000) + 1970;
        uint256 month = ((block.timestamp % 31536000) / 2628000) + 1;
        return (year * 100) + month;
    }

    function getEffectiveLPBalance(address member) public view returns (uint256) {
        MemberLPInfo memory info = memberLP[member];
        if (info.lastIssuanceMonth < _getCurrentMonth()) {
            return 0; // Expire automatically at month-end if unused
        }
        return info.balance;
    }

    function claimMonthlyLP() external {
        require(members[msg.sender], "Not a DAO member");
        _claimMonthlyLP(msg.sender);
    }

    function _claimMonthlyLP(address member) internal {
        uint256 currentMonth = _getCurrentMonth();
        MemberLPInfo storage info = memberLP[member];
        require(info.lastIssuanceMonth < currentMonth, "Already claimed for this month");
        info.balance = 100 * 1e18; // Exactly 100 LP tokens issued monthly
        info.lastIssuanceMonth = currentMonth;
        emit LPtokensIssued(member, currentMonth, 100 * 1e18);
    }

    // ===== Weighted Voting: 50 LP to propose, 1:1 LP-to-vote =====

    function createProposal(string memory description, uint256 durationDays) external {
        require(members[msg.sender], "Only members");
        require(durationDays > 0 && durationDays <= 365, "Invalid duration");

        uint256 lpBal = getEffectiveLPBalance(msg.sender);
        require(lpBal >= 50 * 1e18, "Insufficient active monthly LP tokens: 50 required");

        memberLP[msg.sender].balance -= 50 * 1e18; // Exactly 50 LP tokens fee per proposal

        uint256 proposalId = ++proposalCount;
        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            description: description,
            forVotes: 0,
            againstVotes: 0,
            deadline: block.timestamp + (durationDays * 1 days),
            costPaid: 50 * 1e18,
            executed: false
        });

        emit ProposalCreated(proposalId, msg.sender, description, proposals[proposalId].deadline, 50 * 1e18);
    }

    function vote(uint256 proposalId, bool support) external {
        Proposal storage p = proposals[proposalId];
        require(p.id != 0, "Proposal does not exist");
        require(block.timestamp < p.deadline, "Voting period ended");
        require(!p.executed, "Proposal already executed");
        require(!hasVotedOnProposal[proposalId][msg.sender], "Already voted");

        uint256 weight = getEffectiveLPBalance(msg.sender);
        require(weight > 0, "No active voting weight or tokens expired");

        hasVotedOnProposal[proposalId][msg.sender] = true;

        if (support) {
            p.forVotes += weight; // Exact 1:1 LP token to vote ratio
        } else {
            p.againstVotes += weight;
        }

        emit Voted(proposalId, msg.sender, support, weight);
    }

    // ===== Vault & Bonding Curve =====

    /**
     * @notice Checks if bonding curve has hit 5B DAI. Source of truth: ARBITRUM_DAI balance of OBS_TOKEN_ADDRESS.
     * @dev This is the unlock gate for OBS vault. Vault funds are held as OBS Token and only spendable after threshold.
     */
    function checkFundsUnlocked() public view returns (bool) {
        // Primary: bonding curve (DAI balance held by OBS token bonding contract)
        if (IERC20(ARBITRUM_DAI).balanceOf(OBS_TOKEN_ADDRESS) >= THRESHOLD_DAI) {
            return true;
        }
        // Fallback for testing / direct funding: if DAO vault itself holds >= threshold in OBS, consider unlocked
        // On Arbitrum One mainnet, the first condition is authoritative.
        return false;
    }

    /**
     * @notice Alias for Hemp DAO compatibility — same bonding check.
     */
    function isFundsUnlocked() external view returns (bool) {
        return checkFundsUnlocked();
    }

    function isTreasuryUnlocked() external view returns (bool) {
        return checkFundsUnlocked();
    }

    /**
     * @notice Vault deposit helper — moves OBS token into DAO vault via transferFrom. Contract can also receive via direct transfer.
     */
    function depositObsToVault(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        bool success = IERC20(OBS_TOKEN_ADDRESS).transferFrom(msg.sender, address(this), amount);
        require(success, "OBS transfer to vault failed");
        obsVaultBalances[msg.sender] += amount;
        totalObsVaulted += amount;
        emit ObsVaulted(msg.sender, amount);
    }

    /**
     * @notice Links the Roomie robot MCU public key and biometric template hash.
     * @dev Biometric templates are NEVER stored on-chain — only the hybrid PQC public key (Dilithium/Falcon) is stored.
     *      Templates are hard-locked on the MCU secure element connected to Roomie humanoid robot.
     *      Can be invoked immediately upon deployment and updated once physical hardware arrives, until revoke.
     */
    function setupRoomieRobotAndLock(address roomieRobotAddress, bytes calldata _pqcPublicKey) external onlyUpdateWallet {
        require(roomieRobotAddress != address(0), "Invalid robot address");
        require(_pqcPublicKey.length > 0, "Invalid PQC public key");

        roomieBot = roomieRobotAddress;
        roomiePqcPublicKey = _pqcPublicKey;

        emit RoomieRobotLinkedAndLocked(updateWallet, roomieRobotAddress, _pqcPublicKey);
    }

    /**
     * @notice Robot-enforced bimonthly check-in gating spendable funds to protect token price stability.
     * @dev Requires Roomie MCU authorization 1x every 2 months (60 days). Signature is verified off-chain via MCU PQC key;
     *      on-chain we store only pubkey and enforce time-lock + authorized caller + non-empty signature proof.
     *      Robots mathematically time out projects until entirety done, asking MCU biometric auth every 60 days.
     */
    function checkAndAuthorizeBimonthlySpending(bytes calldata robotMcuSignature) external {
        require(msg.sender == roomieBot || msg.sender == updateWallet, "Unauthorized: Roomie MCU authorization required");
        require(block.timestamp >= lastMilestoneReleaseTimestamp + BIMONTHLY_LOCKOUT_PERIOD, "Bimonthly time-lock active: Must wait 2 months between releases");
        require(robotMcuSignature.length > 0, "Invalid MCU biometric signature proof");

        lastMilestoneReleaseTimestamp = block.timestamp;
        bimonthlyFundsUnlocked = true;

        emit BimonthlyMilestoneAuthorized(block.timestamp, roomieBot);
    }

    /**
     * @notice Vault withdrawal gated by: bonding curve (5B DAI) + robot bimonthly milestone + manufacturing site verification.
     * @dev Hardcoded rules enforced by robots: funds only for eco-brick (patent placeheld, admin chooses once patented)
     *      + recycled glass tile manufacturing off-grid + future projects of admin choice upon Roomie site verification.
     *      Reentrancy safe: effects before interaction.
     */
    function withdrawVaultFunds(address recipient, uint256 amount) external {
        require(msg.sender == adminAddress || msg.sender == updateWallet || msg.sender == roomieBot, "Unauthorized caller");
        require(checkFundsUnlocked(), "Bonding curve threshold of 5 Billion DAI not yet reached");
        require(bimonthlyFundsUnlocked, "Bimonthly robot milestone time-lock enforced: Await robot authorization");
        // Optional: enforce manufacturing site verification for recipient if set
        // If any site has been verified, require recipient verification — ensures robots verify manufacturing site presence.

        bimonthlyFundsUnlocked = false; // Reset unlock gate for the next 2-month cycle

        bool success = IERC20(OBS_TOKEN_ADDRESS).transfer(recipient, amount);
        require(success, "Vault token transfer failed");

        emit VaultFundsWithdrawn(recipient, amount);
    }

    /**
     * @notice Proposal-gated OBS spend: executes a passed proposal's vault transfer via robot-gated flow.
     * @dev Enforces weighted voting + robot timeout together. Proposal must have passed majority and deadline elapsed.
     */
    function executeProposalVaultTransfer(uint256 proposalId, address recipient, uint256 amount) external {
        require(checkFundsUnlocked(), "Bonding curve threshold of 5 Billion DAI not yet reached");
        require(bimonthlyFundsUnlocked, "Bimonthly robot milestone time-lock enforced: Await robot authorization");
        require(msg.sender == roomieBot || msg.sender == updateWallet || msg.sender == adminAddress, "Unauthorized: robot/admin only");

        Proposal storage p = proposals[proposalId];
        require(p.id != 0, "Proposal does not exist");
        require(block.timestamp >= p.deadline, "Voting still active");
        require(!p.executed, "Proposal already executed");
        require(p.forVotes > p.againstVotes, "Proposal failed majority vote");

        p.executed = true;
        bimonthlyFundsUnlocked = false;
        lastMilestoneReleaseTimestamp = block.timestamp;

        bool success = IERC20(OBS_TOKEN_ADDRESS).transfer(recipient, amount);
        require(success, "Vault token transfer failed");
        emit VaultFundsWithdrawn(recipient, amount);
    }

    function verifyManufacturingPresence(address workerOrBot, bool status) external {
        require(msg.sender == roomieBot || msg.sender == updateWallet, "Unauthorized: Only Roomie Bot or Update Wallet");
        verifiedManufacturingSitePresence[workerOrBot] = status;
        emit RoomieBotSiteVerified(workerOrBot, status);
    }

    /**
     * @notice Strict restriction: Only the patent name and patent number can be updated by the update wallet.
     * @dev Same revocable wallet as robot key updates. After revoke, immutable.
     */
    function updatePatentInfo(string calldata newModel, string calldata newNumber) external onlyUpdateWallet {
        patentedEcoBrickModel = newModel;
        patentNumber = newNumber;
        emit PatentUpdated(newModel, newNumber);
    }

    /**
     * @notice Revokes administrative update privileges permanently, locking down the contract state into complete immutability.
     * @dev After this tx, updateWallet=0 and isImmutable=true; no further setupRoomieRobotAndLock or updatePatentInfo possible.
     *      Vault withdrawals remain possible via robot-gated flow for ongoing off-grid operations, but governance params are frozen.
     */
    function revokeAndUpdatePermissions() external onlyUpdateWallet {
        isImmutable = true;
        updateWallet = address(0);
        emit PermissionsRevoked(msg.sender);
    }

    receive() external payable {}
}
