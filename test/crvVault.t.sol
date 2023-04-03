
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import "../src/crvVault.sol";

contract vaultTests is Test {
    crvVault public vault;
    uint256 mainnetFork;

    IERC20 steCRV = IERC20(0x06325440D014e39736583c165C2963BA99fAf14E);
    IERC20 crvToken = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 ldoToken = IERC20(0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32);

    ICurveGauge crvStGauge = ICurveGauge(0x182B723a58739a9c974cFDB385ceaDb237453c28);
    ICurvePool crvPool = ICurvePool(0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511);
    ICurvePool ldoPool = ICurvePool(0x9409280DC1e6D33AB7A8C6EC03e5763FB61772B5);
    ICurvePool stEthPool = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    address constant impersonatedAddress = 0x82a7E64cdCaEdc0220D0a4eB49fDc2Fe8230087A;
    address constant crvOwnerAddress = 0x32D03DB62e464c9168e41028FFa6E9a05D8C6451;
    address constant ldoOwnerAddress = 0xb842aFD82d940fF5D8F6EF3399572592EBF182B0;

    function setUp() public {
        mainnetFork = vm.createFork('https://dry-empty-isle.discover.quiknode.pro/a7a3ca9a22540fc7b61b5e0842c36b9012602a95/');
        vm.selectFork(mainnetFork);
        vault = new crvVault(
            0x06325440D014e39736583c165C2963BA99fAf14E,
            0xD533a949740bb3306d119CC777fa900bA034cd52,
            0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32,
            0x182B723a58739a9c974cFDB385ceaDb237453c28,
            0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511,
            0x9409280DC1e6D33AB7A8C6EC03e5763FB61772B5,
            0xDC24316b9AE028F1497c275EB9192a3Ea0f67022
        );
        
    }

    function testStake() public {
        setUp();
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);
        vm.rollFork(16_800_000);
        assertEq(block.number, 16_800_000); 

        uint256 amount = 100e18;
        emit log_named_uint("Impersonated Address LP Token Balance before staking:", steCRV.balanceOf(impersonatedAddress));
        vm.prank(impersonatedAddress);
        steCRV.approve(address(vault), amount);
        vm.prank(impersonatedAddress);
        vault.stakeLp(amount);
        emit log_named_uint("Impersonated Address LP Token Balance after staking:", steCRV.balanceOf(impersonatedAddress));
    }

    function testUnstake() public {
        setUp();
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);
        vm.rollFork(16_800_000);
        assertEq(block.number, 16_800_000);  
        uint256 amount = 100e18;

        vm.prank(impersonatedAddress);
        steCRV.approve(address(vault), amount);

        emit log_named_uint("Impersonated Address LP Token Balance before staking:", steCRV.balanceOf(impersonatedAddress));
        emit log_named_uint("Impersonated Address Balance before staking:", ldoToken.balanceOf(impersonatedAddress));
        emit log_named_uint("Vault LDO Balance before staking:", ldoToken.balanceOf(address(vault)));

        // Stake Function Call
        vm.prank(impersonatedAddress);
        vault.stakeLp(amount);
        emit log_named_uint("Impersonated Address LP Token Balance after staking:", steCRV.balanceOf(impersonatedAddress));
        
        // Unstake Function call
        vm.rollFork(16_850_400);
        assertEq(block.number, 16_850_400);      
        vm.prank(impersonatedAddress);
        vault.unstakeLp();
        emit log_named_uint("Impersonated Address LDO Balance after withdraw:", ldoToken.balanceOf(impersonatedAddress));
        emit log_named_uint("Impersonated Address LP Token Balance after withdraw:", steCRV.balanceOf(impersonatedAddress));
        emit log_named_uint("Vault Address LP Balance after withdraw:", steCRV.balanceOf(address(vault)));
    }

    function testCompundInvestment() public {
        setUp();
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);
        vm.rollFork(16_800_000);
        assertEq(block.number, 16_800_000);  
        uint256 amount = 100e18;

        emit log_named_uint("Impersonated Address LP Token Balance before staking:", steCRV.balanceOf(impersonatedAddress));
        
        vm.prank(impersonatedAddress);
        steCRV.approve(address(vault), amount);

        emit log_named_uint("Vault LDO Balance before staking:", ldoToken.balanceOf(address(vault)));

        vm.prank(impersonatedAddress);
        vault.stakeLp(amount);
        emit log_named_uint("Impersonated Address LP Token Balance after staking:", steCRV.balanceOf(impersonatedAddress));
               
        emit log_named_uint("Vault Address Compounded LP Token Balance before reInvesting Rewards:", vault.vaultCompoundedLp());
        vm.rollFork(16_850_400);
        assertEq(block.number, 16_850_400);
        vault.reInvestRewards();
        emit log_named_uint("Vault Address Compounded LP Token Balance after reInvesting Rewards:", vault.vaultCompoundedLp());
    }

    function testStakeThenUnstakeAfterCompound() public {
        setUp();
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);
        vm.rollFork(16_800_000);
        assertEq(block.number, 16_800_000);  
        uint256 amount = 100e18;
        
        vm.prank(impersonatedAddress);
        steCRV.approve(address(vault), amount);

        vm.prank(impersonatedAddress);
        vault.stakeLp(amount);
        emit log_named_uint("Impersonated Address LP Token Balance after staking:", steCRV.balanceOf(impersonatedAddress));
               
        vm.rollFork(16_850_400);
        assertEq(block.number, 16_850_400);
        vault.reInvestRewards();

        vm.prank(impersonatedAddress);
        vault.unstakeLp();
        emit log_named_uint("Impersonated Address LDO Balance after withdraw:", ldoToken.balanceOf(impersonatedAddress));
        emit log_named_uint("Impersonated Address LP Token Balance after withdraw:", steCRV.balanceOf(impersonatedAddress));
        emit log_named_uint("Vault Address LP Balance after withdraw:", steCRV.balanceOf(address(vault)));
    }

    function testFarmCrvLdo() public {
        setUp();
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);
        vm.rollFork(16_800_000);
        assertEq(block.number, 16_800_000);  
        uint256 amount = 100e18;

        vm.prank(crvOwnerAddress);
        crvToken.transfer(ldoOwnerAddress, amount);

        vm.prank(ldoOwnerAddress);
        crvToken.approve(address(vault), amount);
        vm.prank(ldoOwnerAddress);
        ldoToken.approve(address(vault), amount);
        vm.prank(ldoOwnerAddress);
        vault.farmCrvLdoRewards(amount, amount);
    }

    function testUnstakeAfterFarmingClvLdo() public {
        setUp();
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);
        vm.rollFork(16_800_000);
        assertEq(block.number, 16_800_000);  
        uint256 amount = 100e18;

        vm.prank(crvOwnerAddress);
        crvToken.transfer(ldoOwnerAddress, amount);

        vm.prank(ldoOwnerAddress);
        crvToken.approve(address(vault), amount);
        vm.prank(ldoOwnerAddress);
        ldoToken.approve(address(vault), amount);
        vm.prank(ldoOwnerAddress);
        vault.farmCrvLdoRewards(amount, amount);

        emit log_named_uint("Impersonated Address LP Token Balance after staking:", steCRV.balanceOf(ldoOwnerAddress));

        vm.rollFork(16_850_400);
        assertEq(block.number, 16_850_400);      
        vm.prank(ldoOwnerAddress);
        vault.unstakeLp();
        emit log_named_uint("Impersonated Address LP Token Balance after staking:", steCRV.balanceOf(ldoOwnerAddress));
    }

    function testEmergencyWithdraw() public {
        setUp();
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);
        vm.rollFork(16_800_000);
        assertEq(block.number, 16_800_000);  
        uint256 amount = 100e18;

        vm.prank(impersonatedAddress);
        steCRV.approve(address(vault), amount);

        vm.prank(impersonatedAddress);
        vault.stakeLp(amount);
               
        vm.rollFork(16_850_400);
        assertEq(block.number, 16_850_400);
        vault.reInvestRewards();

        vault.emergencyWithdraw();
        emit log_named_uint("Owner Address LP Token Balance after emergency withdrawal:", steCRV.balanceOf(vault.owner()));
    }

}