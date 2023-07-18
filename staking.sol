// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


// interface IGenealogyContract {
//     function hasChild(address _user) external payable returns (bool);
// }

contract StakingContractFactory is Ownable {
    address[] public contracts;
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

    function getContractCount() external payable returns(uint contractCount) {
        return contracts.length;
    }

    function getTotalUserStake(address _user) external payable returns (uint totalStake) {
        totalStake = 0;
        for (uint i = 0; i < contracts.length; i++) {
            totalStake += StakingContract(contracts[i]).getStake(_user);
        }
        return totalStake;
    }

    function newStakingContract(address _token, uint _duration, uint _rewardDuration, uint _minDeposit, uint _maxDeposit, uint _rewardRatio) external payable onlyOwner returns(address newContract) {
        StakingContract c = new StakingContract(_token, _duration, _rewardDuration, _minDeposit, _maxDeposit, _rewardRatio);
        contracts.push(address(c));
        emit StakingContractCreated(address(c));
        return address(c);
    }

    function getTotalUserRewards(address _user) external payable returns (uint totalRewards) {
        totalRewards = 0;
        for (uint i = 0; i < contracts.length; i++) {
            totalRewards += StakingContract(contracts[i]).getReward(_user);
        }
        return totalRewards;
    }

    function issueAllRewards() external payable onlyOwner {
        for(uint256 i = 0; i < contracts.length; i++) {
            StakingContract(contracts[i]).issueRewards();
        }
    }

    function setGenealogyContract(address _genealogyContract) external payable onlyOwner {
        for (uint i = 0; i < contracts.length; i++) {
            StakingContract(contracts[i]).setGenealogyContract(_genealogyContract);
        }
    }

    function getUserDetails(address _user) external payable returns (uint totalStake, uint totalRewards) {
        require(msg.sender == _user || msg.sender == owner(), "Access denied");
        for (uint i = 0; i < contracts.length; i++) {
            totalStake += StakingContract(contracts[i]).stakes(_user);
            totalRewards += StakingContract(contracts[i]).totalRewards(_user);
        }
    }

    function getContractUsers(address _contract) external payable onlyOwner returns(address[] memory) {
        return StakingContract(_contract).getAllUsers();
    }

    function isStaker(address _user) external payable returns(bool){
        for(uint i=0;i<contracts.length;i++){
            if(StakingContract(contracts[i]).isStaker(_user)){
                return true;
            }
        }
        return false;
    }

    function getUserContracts(address _user) external payable returns(address[] memory userContracts) {
        require(msg.sender == _user || msg.sender == owner(), "Access denied");
        for(uint i = 0; i < contracts.length; i++) {
            if(StakingContract(contracts[i]).isStaker(_user)) {
                userContracts[userContracts.length] = contracts[i];
            }
        }
    }

    function getContractDetails() external payable onlyOwner returns (ContractDetails[] memory) {
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
    address public genealogyContract; // Add this line
    uint public stakingDuration;
    uint public rewardDuration;
    uint public minDeposit;
    uint public maxDeposit;
    uint public rewardRatio;
    mapping(address => uint) public stakes;
    mapping(address => uint) public stakingStartTimes;
    mapping(address => uint) public lastRewardIssueTimes;
    mapping(address => uint) public totalRewards;
    address[] public stakers;

    event Stake(address indexed user, uint amount);
    event Withdraw(address indexed user, uint256 amount);
    event RewardIssued(address indexed user, uint256 reward);

    constructor(address _token, uint _duration, uint _rewardDuration, uint _minDeposit, uint _maxDeposit, uint _rewardRatio) payable {
        token = IERC20(_token);
        stakingDuration = _duration;
        rewardDuration = _rewardDuration;
        minDeposit = _minDeposit;
        maxDeposit = _maxDeposit;
        rewardRatio = _rewardRatio;
    }

    function stakeTokens(uint256 _amount) external payable {
        require(_amount >= minDeposit && _amount <= maxDeposit, "Invalid deposit amount");
        token.transferFrom(msg.sender, address(this), _amount);
        if(stakes[msg.sender] == 0) {
            stakers.push(msg.sender);
        }
        stakes[msg.sender] += _amount;
        stakingStartTimes[msg.sender] = block.timestamp;
        lastRewardIssueTimes[msg.sender] = block.timestamp;
        emit Stake(msg.sender, _amount);
    }

    function getStake(address _user) external payable returns (uint256) {
        return stakes[_user];
    }

    function getReward(address _user) external payable returns (uint256) {
        return totalRewards[_user];
    }

    function issueRewards() external payable onlyOwner {
        for (uint256 i = 0; i < stakers.length; i++) {
            address staker = stakers[i];
            if (stakingStartTimes[staker]+stakingDuration<block.timestamp){
                continue ;
            }
            else if (lastRewardIssueTimes[staker]<block.timestamp-rewardDuration){
                uint256 rewardCount = (block.timestamp - lastRewardIssueTimes[staker])/rewardDuration;
                uint256 reward = rewardRatio * stakes[staker] * rewardCount/100;
                token.transfer(staker, reward);
                totalRewards[staker] += reward;
                lastRewardIssueTimes[staker] = block.timestamp;
                emit RewardIssued(staker, reward);
                }
            }
        }

    function setGenealogyContract(address _genealogyContract) external payable onlyOwner {
        genealogyContract = _genealogyContract;
    }

    function withdrawTokens() external payable {
        require(stakes[msg.sender] > 0, "No stakes found");
        require(stakingStartTimes[msg.sender] + 90 days > block.timestamp, "you passed 3 month");
        require(!hasChild(msg.sender), "User with children cannot cancel staking");
        token.transfer(msg.sender,stakes[msg.sender]-totalRewards[msg.sender]);
        emit Withdraw(msg.sender, stakes[msg.sender]-totalRewards[msg.sender]);
        for (uint256 i = 0; i < stakers.length; i++) {
            if (stakers[i] == msg.sender) {
                stakers[i] = stakers[stakers.length - 1];
                stakers.pop();
                break;
            }
        }
        stakes[msg.sender] = 0;
    }

    function hasChild(address user) public returns (bool) {
        (bool success, bytes memory result) = genealogyContract.call(abi.encodeWithSignature("hasChild(address)", user));

        // If the call was successful, decode the result and return it
        // If the call failed for any reason, return false
        return abi.decode(result, (bool));
}

    function isStaker(address _address) external payable returns(bool) {
        if (stakes[_address]>0){
            return true;
        }
        else return false;
    }

    function getAllUsers() external payable returns (address[] memory) {
        return stakers;
    }
}
