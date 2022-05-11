// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./token_mappings/RubyToken.sol";

import "./libraries/SafeERC20.sol";
import "hardhat/console.sol";

import "./amm/interfaces/IUniswapV2ERC20.sol";
import "./amm/interfaces/IUniswapV2Pair.sol";
import "./amm/interfaces/IUniswapV2Factory.sol";
import "./interfaces/IRubyStaker.sol";


contract RubyMaker is OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IUniswapV2Factory public factory;
    IRubyStaker public rubyStaker;
    address public rubyToken;
    address public usdToken; // USD token (USDP initially)

    uint256 public burnPercent;

    event Convert(
        address indexed server,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 amountRubyDistributed,
        uint256 amountRubyBurned
    );

    event BurnPercentSet(uint256 newBurnPercent);

    event RubyTokenSet(address rubyToken);

    event UsdTokenSet(address usdToken);

    event AmmFactorySet(address factory);

    event RubyStakerSet(address rubyStaker);

    event PairWithdrawn(address indexed pair, uint256 amountWithdrawn);

    function initialize(
        address _owner,
        address _factory, 
        address _rubyStaker, 
        address _rubyToken, 
        address _usdToken,
        uint256 _burnPercent
        ) external initializer() { 
        require(_owner != address(0), "RubyMaker: Invalid owner address");
        require(_factory != address(0), "RubyMaker: Invalid AMM factory address.");
        require(_rubyStaker != address(0), "RubyMaker: Invalid rubyStaker address.");
        require(_rubyToken != address(0), "RubyMaker: Invalid rubyToken address.");
        require(_usdToken != address(0), "RubyMaker: Invalid USD token address.");
        require(_burnPercent >= 0 && _burnPercent <= 100, "RubyMaker: Invalid burn percent.");

        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);
    
        factory = IUniswapV2Factory(_factory);
        rubyStaker = IRubyStaker(_rubyStaker);
        rubyToken = _rubyToken;
        IERC20(_rubyToken).approve(_rubyStaker, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        usdToken = _usdToken;

        // Note: Percentages are defined with 3 decimals (20% is defined as 20)
        // 0.05% (1/6th) of the total fees (0.30%) are sent to the RubyMaker
        // 0.04% of these fees (80%) are converted to Ruby and sent to the RubyStaker
        // 0.01% of these fees (20%) are burned
        burnPercent = _burnPercent;
    }

    function setBurnPercent(uint256 newBurnPercent) external onlyOwner {
        require(newBurnPercent >= 0 && newBurnPercent <= 100, "RubyMaker: Invalid burn percent.");
        burnPercent = newBurnPercent;
        emit BurnPercentSet(newBurnPercent);
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
        require(token0 != address(0), "RubyMaker: token0 cannot be the zero address.");
        require(token1 != address(0), "RubyMaker: token1 cannot be the zero address.");
        require(token0 != token1, "RubyMaker: token0 and token1 cannot be the same token.");

        // We only support pairs where the one of the token is usdToken or rubyToken
        // when this changes, this needs to be modified along with the _convertStep function
        bool token0supported = (token0 == usdToken || token0 == rubyToken);
        bool token1supported = (token1 == usdToken || token1 == rubyToken);
        require(token0supported || token1supported, "RubyMaker: Conversion unsupported.");
        // Interactions
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(token0, token1));
        require(address(pair) != address(0), "RubyMaker: Invalid pair.");

        IERC20(address(pair)).safeTransfer(address(pair), pair.balanceOf(address(this)));

        (uint256 amount0, uint256 amount1) = pair.burn(address(this));
        if (token0 != pair.token0()) {
            (amount0, amount1) = (amount1, amount0);
        }
        uint256 totalConvertedRuby = _convertStep(token0, token1, amount0, amount1);

        uint256 rubyToBurn = (totalConvertedRuby.mul(burnPercent)).div(100);

        uint256 rubyRewards = totalConvertedRuby - rubyToBurn;

        if(rubyToBurn > 0) {
            // Burn rubyToken
            RubyToken(rubyToken).burn(rubyToBurn);
        }

        if(rubyRewards > 0) {
            rubyStaker.notifyRewardAmount(1, rubyRewards);
        }

        emit Convert(msg.sender, token0, token1, amount0, amount1, rubyRewards, rubyToBurn);
    }

    function _convertStep(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 rubyOut) {
        // Interactions
         if (token0 == rubyToken) {
            // eg. RUBY - USDP
            rubyOut = _toRUBY(token1, amount1).add(amount0);
        } else if (token1 == rubyToken) {
            // eg. USDP - RUBY
            rubyOut = _toRUBY(token0, amount0).add(amount1);
        } else if (token0 == usdToken) {
            // eg. USDP - XYZ
            uint256 usdSwapAmount = _swap(token1, usdToken, amount1, address(this));
            uint256 usdToRubyAmount = usdSwapAmount.add(amount0);
            rubyOut = _toRUBY(usdToken, usdToRubyAmount);
        } else {
            // token1 == usdToken
            // eg. XYZ - USDP
            uint256 usdSwapAmount = _swap(token0, usdToken, amount0, address(this));
            uint256 usdToRubyAmount = usdSwapAmount.add(amount1);
            rubyOut = _toRUBY(usdToken, usdToRubyAmount);
        }
    }

    function _swap(
        address fromToken,
        address toToken,
        uint256 amountIn,
        address to
    ) internal returns (uint256 amountOut) {
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(fromToken, toToken));
        require(address(pair) != address(0), "RubyMaker: Invalid pair.");

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
        amountOut = _swap(token, rubyToken, amountIn, address(this));
    }


    // ADMIN functions
    function setRubyToken(address newRubyToken) external onlyOwner {
        require(newRubyToken != address(0), "RubyMaker: Invalid rubyToken token address.");
        require(isContract(newRubyToken), "RubyMaker: newRubyToken is not a contract address.");
        rubyToken = newRubyToken;
        emit RubyTokenSet(newRubyToken);
    }


    function setUsdToken(address newUsdToken) external onlyOwner {
        require(newUsdToken != address(0), "RubyMaker: Invalid USD token address.");
        require(isContract(newUsdToken), "RubyMaker: newUsdToken is not a contract address.");
        usdToken = newUsdToken;
        emit UsdTokenSet(newUsdToken);
    }

    function setRubyStaker(address newRubyStaker) external onlyOwner {
        require(newRubyStaker != address(0), "RubyMaker: Invalid rubyStaker address.");
        require(isContract(newRubyStaker), "RubyMaker: newRubyStaker is not a contract address.");
        rubyStaker = IRubyStaker(newRubyStaker);
        emit RubyStakerSet(newRubyStaker);
    }

    function setAmmFactory(address newFactory) external onlyOwner {
        require(newFactory != address(0), "RubyMaker: Invalid AMM factory address.");
        require(isContract(newFactory), "RubyMaker: newFactory is not a contract address.");
        factory = IUniswapV2Factory(newFactory);
        emit AmmFactorySet(newFactory);
    }

    function withdrawLP(address pair) external onlyOwner {
        require(pair != address(0), "RubyMaker: Invalid pair address.");
        require(isContract(pair), "RubyMaker: pair is not a contract address.");
        IERC20 _pair = IERC20(pair);
        uint256 pairBalance = _pair.balanceOf(address(this));
        _pair.safeTransfer(owner(), pairBalance);
        emit PairWithdrawn(pair, pairBalance);
    }

    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }

}
