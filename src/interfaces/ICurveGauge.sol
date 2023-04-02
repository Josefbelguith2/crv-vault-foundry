pragma solidity ^0.8.17;

interface ICurveGauge {

    function claim_rewards() external returns (uint256);

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);

}