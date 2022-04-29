// SPDX-License-Identifier: MIT
// author: yoyoismee.eth -- it's opensource but also feel free to send me coffee/beer.
//  ╔═╗┌─┐┌─┐┌─┐┌┬┐┌┐ ┌─┐┌─┐┌┬┐┌─┐┌┬┐┬ ┬┌┬┐┬┌─┐
//  ╚═╗├─┘├┤ ├┤  ││├┴┐│ │├─┤ │ └─┐ │ │ │ ││││ │
//  ╚═╝┴  └─┘└─┘─┴┘└─┘└─┘┴ ┴ ┴o└─┘ ┴ └─┘─┴┘┴└─┘

pragma solidity 0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/finance/PaymentSplitterUpgradeable.sol";
import "./ISBShipable.sol";

// @dev
contract SBIIPayment is Initializable, PaymentSplitterUpgradeable, ISBShipable {
    string public constant MODEL = "SBII-paymentSplitterU-test";
    bool public allowUpdate;

    function initialize(
        bytes memory initArg,
        uint128 bip,
        address feeReceiver
    ) public override initializer {
        (address[] memory payee, uint256[] memory share) = abi.decode(
            initArg,
            (address[], uint256[])
        );
        __PaymentSplitter_init(payee, share);
        // no fee no fee feeReceiver
    }
}
