// SPDX-License-Identifier: MIT
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

pragma solidity 0.6.12;

contract Faucet is Ownable {
    uint256 public constant MINT_AMOUNT_ETH = 0.3 ether;

    uint256 public constant MINT_AMOUNT_TOKEN_18 = 20 * 1e18;
    uint256 public constant MINT_AMOUNT_TOKEN_6 = 20 * 1e6;

    address public ruby;
    address public usdp;
    address public usdc;
    address public usdt;
    address public dai;

    constructor(
        address _ruby,
        address _usdp,
        address _usdc,
        address _usdt,
        address _dai
    ) public payable {
        require(_ruby != address(0), "Faucet: Invalid RUBY address");
        require(_usdp != address(0), "Faucet: Invalid USDP address");
        require(_usdc != address(0), "Faucet: Invalid USDC address");
        require(_usdt != address(0), "Faucet: Invalid USDT address");
        require(_dai != address(0), "Faucet: Invalid DAI address");

        ruby = _ruby;
        usdp = _usdp;
        usdc = _usdc;
        usdt = _usdt;
        dai = _dai;
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}

    function mint(address payable receiver) external {
        receiver.transfer(MINT_AMOUNT_ETH);
        IERC20(ruby).transfer(receiver, MINT_AMOUNT_TOKEN_18);
        IERC20(usdp).transfer(receiver, MINT_AMOUNT_TOKEN_18);
        IERC20(dai).transfer(receiver, MINT_AMOUNT_TOKEN_18);
        IERC20(usdc).transfer(receiver, MINT_AMOUNT_TOKEN_6);
        IERC20(usdt).transfer(receiver, MINT_AMOUNT_TOKEN_6);
    }

    function withdraw() public onlyOwner {
        msg.sender.transfer(address(this).balance);

        IERC20(ruby).transfer(msg.sender, IERC20(ruby).balanceOf(address(this)));
        IERC20(usdp).transfer(msg.sender, IERC20(usdp).balanceOf(address(this)));
        IERC20(dai).transfer(msg.sender, IERC20(dai).balanceOf(address(this)));
        IERC20(usdc).transfer(msg.sender, IERC20(usdc).balanceOf(address(this)));
        IERC20(usdt).transfer(msg.sender, IERC20(usdt).balanceOf(address(this)));
    }
}
