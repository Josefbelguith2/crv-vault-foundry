// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/ICurveGauge.sol";
import "./interfaces/ICurvePool.sol";

contract crvVault is Ownable, ReentrancyGuard {

    using Address for address;

    address public steCRV;
    address public crvToken;
    address public ldoToken;

    address public crvStGauge;
    address public crvPool;
    address public ldoPool;
    address public stEthPool;

    uint256 public vaultLpFunds;
    uint256 public vaultCompoundedLp;
    uint256 public vaultLdoRewardFunds;

    mapping(address => uint256) userStakedBalances;

        /* ========== EVENTS ========== */

    event Staked(address indexed user, uint256 amount);
    event Farmed(address indexed user, uint256 crvAmount, uint256 ldoAmount);
    event unstaked(address indexed user, uint256 unstakedLp);
    event TokenAddressesSet(address steCRV, address crvToken, address ldoToken);
    event UtilityAddressesSet(address crvStGauge, address crvPool, address ldoPool, address stEthPool);
    event LpWithdrawn(uint256 amount);
    event LdoWithdrawn(uint256 amount);
    event CrvWithdrawn(uint256 amount);
    event EthWithdrawn(uint256 amount);

        /* ========== CONSTRUCTOR ========== */

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

        /* ========== MUTATIVE FUNCTIONS ========== */

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
            (_crvAmount + _ldoAmount) > 0,
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

        uint ethBalance = address(this).balance;

        // Swaps CRV & LDO into ETH
        IERC20(crvToken).approve(crvPool, crvAmount);
        IERC20(ldoToken).approve(ldoPool, ldoAmount);

        uint256 outputCrv = ICurvePool(crvPool).get_dy(1, 0, crvAmount);
        uint256 outputLdo = ICurvePool(ldoPool).get_dy(1, 0, ldoAmount);
        
        ICurvePool(crvPool).exchange(1, 0, crvAmount, outputCrv, true);
        ICurvePool(ldoPool).exchange(1, 0, ldoAmount, outputLdo, true);

        // Adds Liquidity to the eth/stEth Pool
        uint256 receivedEth = address(this).balance - ethBalance;
        uint256[2] memory amounts = [receivedEth, 0];
        uint256 receivedLP = ICurvePool(stEthPool).add_liquidity{value : receivedEth}(amounts, 0);

        // Stakes received LP Tokens into the Gauge Contract
        userStakedBalances[msg.sender] += receivedLP;
        vaultLpFunds += receivedLP;
        IERC20(steCRV).approve(crvStGauge, receivedLP);
        ICurveGauge(crvStGauge).deposit(receivedLP);

        emit Farmed(msg.sender, _crvAmount, _ldoAmount);
        return true;
    }

    /**
     * @notice Unstakes User's Lp, transfers it back to them along 
     *         with their respective Rewards
     */
    function unstakeLp() external nonReentrant returns (bool) {

        uint256 ratio = _getUserRatio();
        uint256 withdrawableStakedLP = vaultLpFunds * ratio;
        uint256 withdrawableCompoundLP = vaultCompoundedLp * ratio;
        uint256 totLp = withdrawableStakedLP + withdrawableCompoundLP;

        ICurveGauge(crvStGauge).withdraw(totLp);
        IERC20(steCRV).transfer(msg.sender, totLp);

        uint256 vaultLdoFunds = IERC20(ldoToken).balanceOf(address(this));
        uint256 rewardsRatiod = vaultLdoFunds * ratio;
        IERC20(ldoToken).transfer(msg.sender, rewardsRatiod);

        userStakedBalances[msg.sender] -= withdrawableStakedLP;
        vaultLpFunds -= withdrawableStakedLP;
        vaultCompoundedLp -= withdrawableCompoundLP;

        emit unstaked(msg.sender, totLp);
        return true;
    }

        /* ========= HELPERS ========= */

    /**
     * @notice Helper for receibing LDO Staking rewards
     */
    function _getLdoRewards() internal returns (uint256) {
        uint256 beforeCalimLdo = IERC20(ldoToken).balanceOf(address(this));
        ICurveGauge(crvStGauge).claim_rewards();
        uint256 afterClaimLdo = IERC20(ldoToken).balanceOf(address(this));
        uint256 receivedLdo = afterClaimLdo - beforeCalimLdo;
        vaultLdoRewardFunds += receivedLdo;

        return receivedLdo;
    }

        /* ========= VIEWS ========= */

    /**
     * @notice Helper for providing User's ratio of the vault Lp funds for rwards calculation
     */
    function _getUserRatio() internal view returns (uint256) {
        uint256 userBalance = userStakedBalances[msg.sender];
        uint256 ratio = userBalance / vaultLpFunds;

        return ratio;
    }

        /* ========== ADMIN FUNCTIONS ========== */

    /**
     * @notice Re-Invests Received LDO & CRV Rewards for Compound purposes
     * @dev To be implemented within the Chainlink Contract Automation Tool
     *      with daily interval
     */
    function reInvestRewards() external onlyOwner returns (bool) {
        uint256 ldoAmount = _getLdoRewards();
        IERC20(ldoToken).approve(ldoPool, ldoAmount);
        uint256 output = ICurvePool(ldoPool).get_dy(1, 0, ldoAmount);
        ICurvePool(ldoPool).exchange(1, 0, ldoAmount, output, true);
        uint256 ethBalance = address(this).balance;
        uint256[2] memory amounts = [ethBalance, 0];
        uint256 receivedLP = ICurvePool(stEthPool).add_liquidity{value: ethBalance}(amounts, 0);

        IERC20(steCRV).approve(crvStGauge, receivedLP);
        ICurveGauge(crvStGauge).deposit(receivedLP);
        vaultCompoundedLp += receivedLP;

        return true;
    }

    /**
     * @notice Sets Token Contract Addresses
     * 
     * @param _steCrv LP Token - steCrv - address
     * @param _crvToken CRV Token address
     * @param _ldoToken LDO Token address
     */
    function setTokenAddresses(address _steCrv, address _crvToken, address _ldoToken) external onlyOwner returns (bool) {
        require(_steCrv.isContract(), "Invalid LP Token address");
        require(_crvToken.isContract(), "Invalid CRV Token address");
        require(_ldoToken.isContract(), "Invalid LDO Token address");

        steCRV = _steCrv;
        crvToken = _crvToken;
        ldoToken = _ldoToken;
        
        emit TokenAddressesSet(steCRV, crvToken, ldoToken);
        return true;
    }

    /**
     * @notice Sets the utility address (Pools + Gauge) for the vault contract
     * @param _crvStGauge Reward Gauge Address
     * @param _crvPool CRV/ETH Pool address
     * @param _ldoPool LDO/ETH Pool address
     * @param _stEthPool stETH/ETH Pool address
     */
    function setUtilityAddresses(address _crvStGauge, address _crvPool, address _ldoPool, address _stEthPool) external onlyOwner returns (bool) {
        require(_crvStGauge.isContract(), "Invalid Gauge address");
        require(_crvPool.isContract(), "Invalid CRV Pool address");
        require(_ldoPool.isContract(), "Invalid LDO Pool address");
        require(_stEthPool.isContract(), "Invalid stETH Pool address");

        crvStGauge = _crvStGauge;
        crvPool = _crvPool;
        ldoPool = _ldoPool;
        stEthPool = _stEthPool;

        emit UtilityAddressesSet(crvStGauge, crvPool, ldoPool, stEthPool);
        return true;
    }

    /**
     * @notice Executes an emeregency withdraw of all the vaults' funds towards 
     *         the vault owner address.
     */
    function emergencyWithdraw() external onlyOwner returns (bool) {
        // Emergency LP WIthdrawal
        ICurveGauge(crvStGauge).withdraw(vaultLpFunds);
        ICurveGauge(crvStGauge).withdraw(vaultCompoundedLp);

        if (IERC20(steCRV).balanceOf(address(this)) > 0) {
            uint256 amount = IERC20(steCRV).balanceOf(address(this));
            IERC20(steCRV).transfer(owner(), amount);

            emit LpWithdrawn(amount);
        }
        if (IERC20(ldoToken).balanceOf(address(this)) > 0) {
            uint256 amount = IERC20(ldoToken).balanceOf(address(this));
            IERC20(ldoToken).transfer(owner(), amount);

            emit LdoWithdrawn(amount);
        }
        if (IERC20(crvToken).balanceOf(address(this)) > 0) {
            uint256 amount = IERC20(crvToken).balanceOf(address(this));
            IERC20(crvToken).transfer(owner(), amount);

            emit CrvWithdrawn(amount);
        }
        if (address(this).balance > 0) {
            uint256 amount = address(this).balance;
            payable(owner()).transfer(amount);

            emit EthWithdrawn(amount);
        }

        return true;
    }

    receive() external payable {}
}