pragma solidity ^0.8.17;

interface ICurvePool {

    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount) external returns(uint256);

    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 min_amount) external;
    
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy) external; 
}