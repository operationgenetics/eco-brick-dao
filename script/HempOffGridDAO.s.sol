// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HempOffGridDAO} from "../src/HempOffGridDAO.sol";

/**
 * @notice Deployment script for HempOffGridDAO — zero constructor args.
 * @dev Usage: forge script script/HempOffGridDAO.s.sol:HempOffGridDAOScript --rpc-url $ARBITRUM_RPC --broadcast
 *      No details/entry needed besides file path and signing with MetaMask WalletConnect.
 *      Constants (OBS_TOKEN_ADDRESS, DESIGNATED_UPDATE_WALLET 0xaF57..., THRESHOLD_DAI 5B) are hardcoded.
 */
contract HempOffGridDAOScript is Script {
    HempOffGridDAO public dao;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        dao = new HempOffGridDAO();
        vm.stopBroadcast();
    }
}
