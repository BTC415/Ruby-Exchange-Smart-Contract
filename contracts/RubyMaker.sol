// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
import "./token_mappings/RubyToken.sol";

import "./libraries/SafeERC20.sol";
import "hardhat/console.sol";

import "./amm/interfaces/IUniswapV2ERC20.sol";
import "./amm/interfaces/IUniswapV2Pair.sol";
import "./amm/interfaces/IUniswapV2Factory.sol";
import "./interfaces/IRubyStaker.sol";

import "./Ownable.sol";

// RubyMaker is fork of SushiMaker
contract RubyMaker is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IUniswapV2Factory public immutable factory;
    IRubyStaker public immutable rubyStaker;
    address private immutable ruby;
    address private immutable ethc;
    uint256 public burnPercent;

    mapping(address => address) internal _bridges;

    event LogBridgeSet(address indexed token, address indexed bridge);
    event LogConvert(
        address indexed server,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 amountRubyDistributed,
        uint256 amountRubyBurned
    );

    event BurnPercentChanged(uint256 newBurnPercent);

    constructor(
        address _factory,
        address _rubyStaker,
        address _ruby,
        address _ethc,
        uint256 _burnPercent
    ) public {
        require(_factory != address(0), "RubyMaker: Invalid factory address.");
        require(_rubyStaker != address(0), "RubyMaker: Invalid rubyStaker address.");
        require(_ruby != address(0), "RubyMaker: Invalid ruby address.");
        require(_ethc != address(0), "RubyMaker: Invalid ethc address.");
        require(_burnPercent >= 0 && _burnPercent <= 100, "RubyMaker: Invalid burn percent.");

        factory = IUniswapV2Factory(_factory);
        rubyStaker = IRubyStaker(_rubyStaker);
        ruby = _ruby;
        IERC20(_ruby).approve(_rubyStaker, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        ethc = _ethc;

        // Note: Percentages are defined with 3 decimals (20% is defined as 20)
        // 0.05% (1/6th) of the total fees (0.30%) are sent to the RubyMaker
        // 0.04% of these fees (80%) are converted to Ruby and sent to the RubyStaker
        // 0.01% of these fees (20%) are burned
        burnPercent = _burnPercent;
    }

    function setBurnPercent(uint256 newBurnPercent) external onlyOwner {
        require(newBurnPercent >= 0 && newBurnPercent <= 100, "RubyMaker: Invalid burn percent.");
        burnPercent = newBurnPercent;
        emit BurnPercentChanged(newBurnPercent);
    }

    function bridgeFor(address token) public view returns (address bridge) {
        bridge = _bridges[token];
        if (bridge == address(0)) {
            bridge = ethc;
        }
    }

    function setBridge(address token, address bridge) external onlyOwner {
        // Checks
        require(token != ruby && token != ethc && token != bridge, "RubyMaker: Invalid bridge");

        // Effects
        _bridges[token] = bridge;
        emit LogBridgeSet(token, bridge);
    }

    modifier onlyEOA() {
        // Try to make flash-loan exploit harder to do by only allowing externally owned addresses.
        require(msg.sender == tx.origin, "RubyMaker: must use EOA");
        _;
    }

    function convert(address token0, address token1) external onlyEOA {
        _convert(token0, token1);
    }

    function convertMultiple(address[] calldata token0, address[] calldata token1) external onlyEOA {
        // TODO: This can be optimized a fair bit, but this is safer and simpler for now
        uint256 len = token0.length;
        for (uint256 i = 0; i < len; i++) {
            _convert(token0[i], token1[i]);
        }
    }

    function _convert(address token0, address token1) internal {
        // Interactions
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(token0, token1));
        require(address(pair) != address(0), "RubyMaker: Invalid pair");

        IERC20(address(pair)).safeTransfer(address(pair), pair.balanceOf(address(this)));

        (uint256 amount0, uint256 amount1) = pair.burn(address(this));
        if (token0 != pair.token0()) {
            (amount0, amount1) = (amount1, amount0);
        }
        uint256 totalConvertedRuby = _convertStep(token0, token1, amount0, amount1);
        uint256 rubyToBurn = (totalConvertedRuby.mul(burnPercent)).div(100);

        uint256 rubyRewards = totalConvertedRuby - rubyToBurn;

        // Burn ruby
        RubyToken(ruby).burn(rubyToBurn);

        rubyStaker.notifyRewardAmount(1, rubyRewards);

        emit LogConvert(msg.sender, token0, token1, amount0, amount1, rubyRewards, rubyToBurn);
    }

    function _convertStep(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 rubyOut) {
        // Interactions
        if (token0 == token1) {
            uint256 amount = amount0.add(amount1);
            if (token0 == ruby) {
                rubyOut = amount;
            } else if (token0 == ethc) {
                rubyOut = _toRUBY(ethc, amount);
            } else {
                address bridge = bridgeFor(token0);
                amount = _swap(token0, bridge, amount, address(this));
                rubyOut = _convertStep(bridge, bridge, amount, 0);
            }
        } else if (token0 == ruby) {
            // eg. RUBY - ETH
            rubyOut = _toRUBY(token1, amount1).add(amount0);
        } else if (token1 == ruby) {
            // eg. USDT - RUBY
            rubyOut = _toRUBY(token0, amount0).add(amount1);
        } else if (token0 == ethc) {
            // eg. ETH - USDC
            rubyOut = _toRUBY(ethc, _swap(token1, ethc, amount1, address(this)).add(amount0));
        } else if (token1 == ethc) {
            // eg. USDT - ETH
            rubyOut = _toRUBY(ethc, _swap(token0, ethc, amount0, address(this)).add(amount1));
        } else {
            // eg. MIC - USDT
            address bridge0 = bridgeFor(token0);
            address bridge1 = bridgeFor(token1);
            if (bridge0 == token1) {
                // eg. MIC - USDT - and bridgeFor(MIC) = USDT
                rubyOut = _convertStep(bridge0, token1, _swap(token0, bridge0, amount0, address(this)), amount1);
            } else if (bridge1 == token0) {
                // eg. WBTC - DSD - and bridgeFor(DSD) = WBTC
                rubyOut = _convertStep(token0, bridge1, amount0, _swap(token1, bridge1, amount1, address(this)));
            } else {
                rubyOut = _convertStep(
                    bridge0,
                    bridge1, // eg. USDT - DSD - and bridgeFor(DSD) = WBTC
                    _swap(token0, bridge0, amount0, address(this)),
                    _swap(token1, bridge1, amount1, address(this))
                );
            }
        }
    }

    function _swap(
        address fromToken,
        address toToken,
        uint256 amountIn,
        address to
    ) internal returns (uint256 amountOut) {
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(fromToken, toToken));
        require(address(pair) != address(0), "RubyMaker: Cannot convert");

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        uint256 amountInWithFee = amountIn.mul(997);
        if (fromToken == pair.token0()) {
            amountOut = amountInWithFee.mul(reserve1) / reserve0.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(0, amountOut, to, 997, new bytes(0));
            // TODO: Add maximum slippage?
        } else {
            amountOut = amountInWithFee.mul(reserve0) / reserve1.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(amountOut, 0, to, 997, new bytes(0));
            // TODO: Add maximum slippage?
        }
    }

    function _toRUBY(address token, uint256 amountIn) internal returns (uint256 amountOut) {
        amountOut = _swap(token, ruby, amountIn, address(this));
    }
}
