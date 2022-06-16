// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20Capped.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RubyToken with Governance
 * @notice This version of the RubyToken is to be used on the SChain
 * It features access control needed for the IMA TokenManager contract (bridging),
 * and also for the RubyMaker contract (distribute and burn mechanism)
 */
contract RubyToken is ERC20Capped, AccessControl {
    /// @notice Access control roles for the IMA TokenManager
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /// @notice Total number of tokens
    uint256 public constant MAX_SUPPLY = 200_000_000e18; // 200 million Ruby

    /// @notice The total amount of burned Ruby tokens
    uint256 public burnedAmount;

    constructor() public ERC20("RubyToken", "RUBY") ERC20Capped(MAX_SUPPLY) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice Creates `amount` token to `to`. Must only be called by the IMA TokenManager contract
    function mint(address to, uint256 amount) public {
        require(hasRole(MINTER_ROLE, msg.sender), "RUBY::mint: Caller is not a minter");
        _mint(to, amount);
    }

    /// @notice Destroys `amount` of RUBY tokens from the msg.sender. 
    /// Must only be called by the IMA TokenManager contract and the RubyMaker contract
    function burn(uint256 amount) public virtual {
        require(hasRole(BURNER_ROLE, msg.sender), "RUBY::burn: Caller is not a burner");
        _burn(msg.sender, amount);
        burnedAmount += amount;
    }

}
