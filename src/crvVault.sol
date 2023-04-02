// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-0.8/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-0.8/access/Ownable.sol";
import "@openzeppelin/contracts-0.8/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-0.8/utils/Address.sol";
import "./interfaces/ICurveGauge.sol";
import "./interfaces/ICurvePool.sol";

contract crvVault is Ownable, ReentrancyGuard {

    using Address for address;

    address public steCRV;
    address public crvToken;
    address public ldoToken;
    address public eth;

    address public crvStGauge;
    address public crvPool;
    address public ldoPool;
    address public stEthPool;

    uint256 public vaultLpFunds;
    uint256 public vaultCompoundedLp;
    uint256 public vaultLdoRewardFunds;

    mapping(address => uint256) userStakedBalances;

    event Staked(address indexed user, uint256 amount);
    event farmed(address indexed user, uint256 crvAmount, uint256 ldoAmount);
    event unstaked(address indexed user, uint256 unstakedLp);

    constructor(
        address _steCRV,
        address _crvToken,
        address _ldoToken,
        address _crvStGauge,
        address _crvPool,
        address _ldoPool,
        address _stEthPool
    ) {
        require(_steCRV.isContract(), "Invalid LP Token address");
        require(_crvToken.isContract(), "Invalid CRV Token address");
        require(_ldoToken.isContract(), "Invalid LDO Token address");

        require(_crvStGauge.isContract(), "Invalid Gauge address");
        require(_crvPool.isContract(), "Invalid CRV Pool address");
        require(_ldoPool.isContract(), "Invalid LDO Pool address");
        require(_stEthPool.isContract(), "Invalid stETH Pool address");

        steCRV = _steCRV;
        crvToken = _crvToken;
        ldoToken = _ldoToken;
        crvStGauge = _crvStGauge;
        crvPool = _crvPool;
        ldoPool = _ldoPool;
        stEthPool = _stEthPool;
    }

    /**
     * @notice Allows user to stake his LP Tokens -steCrv- into the steCrv Gauge contract
     * 
     * @param _amount Lp Token amount to be staked
     */
    function stakeLp(uint256 _amount) external nonReentrant returns (bool) {

        // Checks
        require(
            _amount > 0, 
            'Cannot stake 0 Tokens'
        );
        require(
            IERC20(steCRV).balanceOf(msg.sender) >= _amount,
            "LP Token balance & requested amount mismatch"
        );
        require(
            IERC20(steCRV).allowance(msg.sender, address(this)) >= _amount, 
            "Requested Amount is not approved"
        );

        // Transfer LP Tokens from user address to Vault
        IERC20(steCRV).transferFrom(msg.sender, address(this), _amount);
        userStakedBalances[msg.sender] += _amount;
        vaultLpFunds += _amount;

        // Stakes User's LP Tokens
        uint256 lpToDeposit = userStakedBalances[msg.sender];
        IERC20(steCRV).approve(crvStGauge, lpToDeposit);
        ICurveGauge(crvStGauge).deposit(lpToDeposit);

        emit Staked(msg.sender, _amount);
        return true;
    }

    /**
     * @notice Allows user to Yield Farm his CRV & LDO Tokens
     * @dev Received CRV & LDO Tokens are swapped to ETH -> Deposited in the eth/stEth Pool 
     *      -> Received steCRV is staked in the Gauge Contract
     * @param _crvAmount CRV Token amount to be farmed
     * @param _ldoAmount LDO Token amount to be farmed
     */
    function farmCrvLdoRewards(uint256 _crvAmount, uint256 _ldoAmount) external nonReentrant returns (bool) {

        // Checks
        require (
            _crvAmount > 0 && _ldoAmount > 0,
            "Cannot farm 0 Tokens"
        );
        require(
            IERC20(crvToken).balanceOf(msg.sender) >= _crvAmount
            &&
            IERC20(ldoToken).balanceOf(msg.sender) >= _ldoAmount,
            "Token Balances and Requested Amounts mismatch"
        );
        require(
            IERC20(crvToken).allowance(msg.sender, address(this)) >= _crvAmount
            &&
            IERC20(ldoToken).allowance(msg.sender, address(this)) >= _ldoAmount,
            "Requested Amounts are not approved"
        );

        // Transfers CRV & LDO Tokens from user to Vault
        IERC20(crvToken).transferFrom(msg.sender, address(this), _crvAmount);
        uint256 crvAmount = IERC20(crvToken).balanceOf(address(this));
        IERC20(ldoToken).transferFrom(msg.sender, address(this), _ldoAmount);
        uint256 ldoAmount = IERC20(ldoToken).balanceOf(address(this));

        // Swaps CRV & LDO into ETH
        ICurvePool(crvPool).exchange(1, 0, crvAmount, crvAmount);
        ICurvePool(ldoPool).exchange(1, 0, ldoAmount, ldoAmount);

        // Adds Liquidity to the eth/stEth Pool
        uint256 ethBalance = address(this).balance;
        uint256[2] memory amounts = [ethBalance, 0];
        uint256 receivedLP = ICurvePool(stEthPool).add_liquidity(amounts, 0);

        // Stakes received LP Tokens into the Gauge Contract
        userStakedBalances[msg.sender] += receivedLP;
        vaultLpFunds += receivedLP;
        IERC20(steCRV).approve(crvStGauge, receivedLP);
        ICurveGauge(crvStGauge).deposit(receivedLP);

        emit farmed(msg.sender, _crvAmount, _ldoAmount);
        return true;
    }

    function unstakeLp() external nonReentrant returns (bool) {

        uint256 ratio = _getUserRatio();
        uint256 withdrawableStakedLP = vaultLpFunds * ratio;
        uint256 withdrawableCompoundLP = vaultCompoundedLp * ratio;
        uint256 totLp = withdrawableStakedLP + withdrawableCompoundLP;

        ICurveGauge(crvStGauge).withdraw(totLp);
        IERC20(steCRV).transfer(msg.sender, totLp);

        userStakedBalances[msg.sender] -= withdrawableStakedLP;
        vaultLpFunds -= withdrawableStakedLP;
        vaultCompoundedLp -= withdrawableCompoundLP;

        emit unstaked(msg.sender, totLp);
        return true;
    }

    /**
     * @notice Re-Invests Received LDO & CRV Rewards for Compound purposes
     * @dev To be implemented within the Chainlink Contract Automation Tool
     *      with daily interval
     */
    function reInvestRewards() external onlyOwner returns (bool) {
        uint256 ldoAmount = _getLdoRewards();
        ICurvePool(ldoPool).exchange(1, 0, ldoAmount, ldoAmount);
        uint256 ethBalance = address(this).balance;
        uint256[2] memory amounts = [ethBalance, 0];
        uint256 receivedLP = ICurvePool(stEthPool).add_liquidity(amounts, 0);

        IERC20(steCRV).approve(crvStGauge, receivedLP);
        ICurveGauge(crvStGauge).deposit(receivedLP);
        vaultCompoundedLp += receivedLP;

        return true;
    }

    /**
     * @notice Helper for receibing LDO Staking rewards
     */
    function _getLdoRewards() internal returns (uint256) {
        uint256 receivedLdo = ICurveGauge(crvStGauge).claim_rewards();
        vaultLdoRewardFunds += receivedLdo;

        return receivedLdo;
    }

    function _getUserRatio() internal view returns (uint256) {
        uint256 userBalance = userStakedBalances[msg.sender];
        uint256 ratio = userBalance / vaultLpFunds;

        return ratio;
    }

    receive() external payable {}
}