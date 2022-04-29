// SPDX-License-Identifier: MIT
// author: yoyoismee.eth -- it's opensource but also feel free to send me coffee/beer.
//  ╔═╗┌─┐┌─┐┌─┐┌┬┐┌┐ ┌─┐┌─┐┌┬┐┌─┐┌┬┐┬ ┬┌┬┐┬┌─┐
//  ╚═╗├─┘├┤ ├┤  ││├┴┐│ │├─┤ │ └─┐ │ │ │ ││││ │
//  ╚═╝┴  └─┘└─┘─┴┘└─┘└─┘┴ ┴ ┴o└─┘ ┴ └─┘─┴┘┴└─┘

pragma solidity 0.8.13;

interface ISBRandomness {
    function getRand(bytes32 seed) external returns (bytes32);
}
