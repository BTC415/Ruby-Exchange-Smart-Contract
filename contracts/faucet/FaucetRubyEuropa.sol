// SPDX-License-Identifier: MIT
import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity 0.6.12;

contract FaucetRubyEuropa is Ownable {
    uint256 public constant MINT_AMOUNT_ETH = 0.1 ether;

    constructor() public payable {}

    receive() external payable {}

    fallback() external payable {}

    function mint(address payable receiver) external {
      uint256 bal = receiver.balance;
      if (bal < MINT_AMOUNT_ETH) {
        receiver.transfer(MINT_AMOUNT_ETH - bal);
      }
    }

    function withdraw() public onlyOwner {
        msg.sender.transfer(address(this).balance);
    }
}
