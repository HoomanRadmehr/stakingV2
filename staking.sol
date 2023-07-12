// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


interface IGenealogyContract {
    function hasChild(address _user) external view returns (bool);
}

contract StakingContractFactory is Ownable {
    address[] public contracts;
    // StakingContract[] public stakingContracts;
    event StakingContractCreated(address contractAddress);

    struct ContractDetails {
        address contractAddress;
        address tokenAddress;
        uint stakingDuration;
        uint rewardDuration;
        uint minDeposit;
        uint maxDeposit;
        uint rewardRatio;
    }

    function getContractCount() public view returns(uint contractCount) {
        return contracts.length;
    }

    function getTotalUserStake(address _user) public view returns (uint totalStake) {
        totalStake = 0;
        for (uint i = 0; i < contracts.length; i++) {
            totalStake += StakingContract(contracts[i]).getStake(_user);
        }
        return totalStake;
    }


    function newStakingContract(address _token, uint _duration, uint _rewardDuration, uint _minDeposit, uint _maxDeposit, uint _rewardRatio) public onlyOwner returns(address newContract) {
        StakingContract c = new StakingContract(_token, msg.sender, _duration, _rewardDuration, _minDeposit, _maxDeposit, _rewardRatio);
        contracts.push(address(c));
        emit StakingContractCreated(address(c));
        return address(c);
    }

    function getTotalUserRewards(address _user) public view returns (uint totalRewards) {
        totalRewards = 0;
        for (uint i = 0; i < contracts.length; i++) {
            totalRewards += StakingContract(contracts[i]).getReward(_user);
        }
        return totalRewards;
    }

    function issueAllRewards() public onlyOwner {
        for(uint256 i = 0; i < contracts.length; i++) {
            StakingContract(contracts[i]).issueRewards();
        }
    }

    function setGenealogyContract(address _genealogyContract) public onlyOwner {
        for (uint i = 0; i < contracts.length; i++) {
            StakingContract(contracts[i]).setGenealogyContract(_genealogyContract);
        }
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

    function getContractDetails() public view onlyOwner returns (ContractDetails[] memory) {
        ContractDetails[] memory contractDetails = new ContractDetails[](contracts.length);
        for (uint i = 0; i < contracts.length; i++) {
            StakingContract sc = StakingContract(contracts[i]);
            contractDetails[i] = ContractDetails({
                contractAddress: address(sc),
                tokenAddress: address(sc.token()),
                stakingDuration: sc.stakingDuration(),
                rewardDuration: sc.rewardDuration(),
                minDeposit: sc.minDeposit(),
                maxDeposit: sc.maxDeposit(),
                rewardRatio: sc.rewardRatio()
            });
        }
        return contractDetails;
    }
}

contract StakingContract is Ownable {

    IERC20 public token;
    address public creator;
    address public genealogyContractAddress;
    uint public stakingDuration;
    uint public rewardDuration;
    uint public minDeposit;
    uint public maxDeposit;
    uint public rewardRatio;
    mapping(address => uint) public stakes;
    mapping(address => uint) public stakingStartTimes;
    mapping(address => uint) public rewardIssueTimes;
    mapping(address => uint) public totalRewards;
    address[] public stakers;
    address[] public users;

    event Stake(address indexed user, uint amount);
    event Withdraw(address indexed user, uint256 amount);
    event RewardIssued(address indexed user, uint256 reward);

    struct StakeDetail {
        uint256 timestamp;
        uint256 amount;
    }

    mapping(address => StakeDetail[]) public stakingDetails;

    constructor(address _token, address _owner, uint _duration, uint _rewardDuration, uint _minDeposit, uint _maxDeposit, uint _rewardRatio) {
        token = IERC20(_token);
        creator = _owner;
        stakingDuration = _duration;
        rewardDuration = _rewardDuration;
        minDeposit = _minDeposit;
        maxDeposit = _maxDeposit;
        rewardRatio = _rewardRatio;
    }

    function stakeTokens(uint256 _amount) public {
        require(_amount >= minDeposit && _amount <= maxDeposit, "Invalid deposit amount");
        token.transferFrom(msg.sender, address(this), _amount);
        if(stakes[msg.sender] == 0) {
            stakers.push(msg.sender);
        }
        stakes[msg.sender] += _amount;
        stakingDetails[msg.sender].push(StakeDetail(block.timestamp, _amount));
        emit Stake(msg.sender, _amount);
    }

    function getStake(address _user) public view returns (uint) {
        return stakes[_user];
    }

    function getReward(address _user) public view returns (uint) {
        return totalRewards[_user];
    }

    function issueRewards() public onlyOwner {
        for (uint256 i = 0; i < stakers.length; i++) {
            address staker = stakers[i];
            for (uint256 j = 0; j < stakingDetails[staker].length; j++) {
                StakeDetail storage stakeDetail = stakingDetails[staker][j];
                if (block.timestamp > stakeDetail.timestamp + rewardDuration) {
                    uint256 reward = (stakeDetail.amount * rewardRatio) / 100;
                    totalRewards[staker] += reward;
                    token.transfer(staker, reward);
                    stakeDetail.timestamp = block.timestamp;
                    emit RewardIssued(staker, reward);
                }
            }
        }
    }

    function setGenealogyContract(address _genealogyContract) public onlyOwner {
        genealogyContractAddress = _genealogyContract;
    }

    function withdrawTokens() public {
        require(stakes[msg.sender] > 0, "No stakes found");
        token.transfer(msg.sender, stakes[msg.sender]);
        emit Withdraw(msg.sender, stakes[msg.sender]);
        for (uint256 i = 0; i < stakers.length; i++) {
            if (stakers[i] == msg.sender) {
                stakers[i] = stakers[stakers.length - 1];
                stakers.pop();
                break;
            }
        }
        stakes[msg.sender] = 0;
    }

    function isStaker(address _address) public view returns(bool) {
        if (stakes[_address]>0){
            return true;
        }
        else return false;
    }

    function getAllUsers() public view returns (address[] memory) {
        return users;
    }
}
