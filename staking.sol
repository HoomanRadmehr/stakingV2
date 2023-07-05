// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract StakingContractFactory is Ownable {
    address[] public contracts;

    event ContractCreated(address contractAddress);

    function getContractCount() public view returns(uint contractCount) {
        return contracts.length;
    }

    function newStakingContract(address _token, uint _duration, uint _rewardDuration, uint _minDeposit, uint _maxDeposit, uint _rewardRatio) public onlyOwner returns(address newContract) {
        StakingContract c = new StakingContract(_token, msg.sender, _duration, _rewardDuration, _minDeposit, _maxDeposit, _rewardRatio);
        contracts.push(address(c));
        emit ContractCreated(address(c));
        return address(c);
    }

    function getUserDetails(address _user) public view returns (uint totalStake, uint totalRewards) {
        require(msg.sender == _user || msg.sender == owner(), "Access denied");
        for (uint i = 0; i < contracts.length; i++) {
            totalStake += StakingContract(contracts[i]).stakes(_user);
            totalRewards += StakingContract(contracts[i]).totalRewards(_user);
        }
    }

    function getContractUsers(address _contract) public view onlyOwner returns(address[] memory) {
        return StakingContract(_contract).getAllUsers();
    }

    function getUserContracts(address _user) public view returns(address[] memory userContracts) {
        require(msg.sender == _user || msg.sender == owner(), "Access denied");
        for(uint i = 0; i < contracts.length; i++) {
            if(StakingContract(contracts[i]).isStaker(_user)) {
                userContracts[userContracts.length] = contracts[i];
            }
        }
    }
}

contract StakingContract is Ownable {
    IERC20 public token;
    address public owner;
    uint public stakingDuration;
    uint public rewardDuration;
    uint public minDeposit;
    uint public maxDeposit;
    uint public rewardRatio;
    mapping(address => uint) public stakes;
    mapping(address => uint) public rewardIssueTimes;
    mapping(address => uint) public totalRewards;
    mapping(address => bool) public stakers;
    address[] public users;

    event Stake(address indexed user, uint amount);
    event RewardIssued(address indexed user, uint amount);
    event StakeCanceled(address indexed user, uint refund);

    constructor(address _token, address _owner, uint _duration, uint _rewardDuration, uint _minDeposit, uint _maxDeposit, uint _rewardRatio) {
        token = IERC20(_token);
        owner = _owner;
        stakingDuration = _duration;
        rewardDuration = _rewardDuration;
        minDeposit = _minDeposit;
        maxDeposit = _maxDeposit;
        rewardRatio = _rewardRatio;
    }

    function stake(uint _amount) public {
        require(_amount >= minDeposit && _amount <= maxDeposit, "Invalid deposit amount");
        stakes[msg.sender] += _amount;
        rewardIssueTimes[msg.sender] = block.timestamp;
        token.transferFrom(msg.sender, address(this), _amount);
        users.push(msg.sender);
        stakers[msg.sender] = true;
        emit Stake(msg.sender, _amount);
    }

    function issueReward() public onlyOwner {
        for(uint i = 0; i < users.length; i++) {
            if(block.timestamp >= rewardIssueTimes[users[i]] + rewardDuration) {
                uint reward = stakes[users[i]] * rewardRatio / 100;
                totalRewards[users[i]] += reward;
                token.transfer(users[i], reward);
                rewardIssueTimes[users[i]] = block.timestamp;
                emit RewardIssued(users[i], reward);
            }
        }
    }

    function cancelStake() public {
        require(stakes[msg.sender] > 0, "No stake to withdraw");
        uint refund = stakes[msg.sender] > totalRewards[msg.sender] ? stakes[msg.sender] - totalRewards[msg.sender] : 0;
        stakes[msg.sender] = 0;
        totalRewards[msg.sender] = 0;
        stakers[msg.sender] = false;
        token.transfer(msg.sender, refund);
        emit StakeCanceled(msg.sender, refund);
    }

    function isStaker(address _address) public view returns(bool) {
        return stakers[_address];
    }

    function getAllUsers() public view returns (address[] memory) {
        return users;
    }
}