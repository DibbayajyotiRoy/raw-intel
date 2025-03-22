// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DeNewsToken
 * @dev ERC20 token for the DeNews platform with reward distribution capabilities
 */
contract DeNewsToken is ERC20, Ownable {
    // Mapping to track user reputation scores
    mapping(address => uint256) public reputationScores;
    
    // Events
    event ReputationIncreased(address indexed user, uint256 amount);
    event RewardDistributed(address indexed user, uint256 amount);
    
    /**
     * @dev Constructor that gives the msg.sender all of existing tokens.
     */
    constructor(uint256 initialSupply) ERC20("DeNews Token", "DNT") Ownable(msg.sender) {
        _mint(msg.sender, initialSupply * 10 ** decimals());
    }
    
    /**
     * @dev Increases a user's reputation score
     * @param user Address of the user
     * @param amount Amount to increase reputation by
     */
    function increaseReputation(address user, uint256 amount) external onlyOwner {
        reputationScores[user] += amount;
        emit ReputationIncreased(user, amount);
    }
    
    /**
     * @dev Distributes rewards to a user based on their contributions
     * @param user Address of the user
     * @param amount Amount of tokens to reward
     */
    function distributeReward(address user, uint256 amount) external onlyOwner {
        require(balanceOf(owner()) >= amount, "Insufficient balance for reward");
        _transfer(owner(), user, amount);
        emit RewardDistributed(user, amount);
    }
    
    /**
     * @dev Returns the reputation score of a user
     * @param user Address of the user
     * @return Reputation score
     */
    function getReputation(address user) external view returns (uint256) {
        return reputationScores[user];
    }
}

