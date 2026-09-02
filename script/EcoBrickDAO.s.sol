// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {EcoBrickDAO} from "../src/EcoBrickDAO.sol";

/**
 * @notice Deployment script for EcoBrickDAO — zero constructor args.
 * @dev Usage: forge script script/EcoBrickDAO.s.sol:EcoBrickDAOScript --rpc-url $ARBITRUM_RPC --broadcast
 *      Or with Ledger/WalletConnect via --ledger / --trezor / --aws etc.
 *      No details required besides correct file path and signing wallet (MetaMask via WalletConnect on One-Click frontends).
 */
contract EcoBrickDAOScript is Script {
    EcoBrickDAO public dao;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        dao = new EcoBrickDAO();
        vm.stopBroadcast();
    }
}
