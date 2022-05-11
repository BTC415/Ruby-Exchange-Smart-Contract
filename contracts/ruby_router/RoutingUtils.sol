// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

enum SwapType {
    AMM,
    STABLE_POOL
}

enum AMMSwapType {
    EXACT_TOKENS_FOR_TOKENS,
    TOKENS_FOR_EXACT_TOKENS
}

struct AMMSwapDetails {
    AMMSwapType swapType;
    uint256 amountIn;
    uint256 amountOut;
    address[] path;
    address to;
    uint256 deadline;
}

struct StableSwapDetails {
    address stablePool;
    uint8 tokenIndexFrom;
    uint8 tokenIndexTo;
    uint256 dx;
    uint256 minDy;
    uint256 deadline;
}

struct SwapDetails {
    AMMSwapDetails[] ammSwaps;
    StableSwapDetails[] stableSwaps;
    SwapType[] order;
}
