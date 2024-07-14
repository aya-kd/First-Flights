// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { TSwapPool } from "../../src/PoolFactory.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract Findings is Test {
    TSwapPool pool;
    ERC20Mock poolToken;
    ERC20Mock weth;

    address liquidityProvider = makeAddr("liquidityProvider");
    address user = makeAddr("user");

    function setUp() public {
        poolToken = new ERC20Mock();
        weth = new ERC20Mock();
        pool = new TSwapPool(address(poolToken), address(weth), "LTokenA", "LA");

        weth.mint(liquidityProvider, 200e18);
        poolToken.mint(liquidityProvider, 200e18);

        weth.mint(user, 20e18);
        poolToken.mint(user, 20e18);
    }

    function testSwapExactOutput() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(user);
        poolToken.approve(address(pool), 20e18);
        // Before swap:
        // 100 pool token, 100 weth, 100 LP token

        // After we swap, there will be ~99 weth, and ~101 pool token
        // x*y=k
        // 100 * 100 = 10,000
        // x * 99 = 10,000 => x = 101

        // Expected user balance = 20-1 = 19
        // Expected user balance due to vulnerability = 20 - 1 * 10 = 10
        uint256 expectedBalance = 10e18;

        pool.swapExactOutput(poolToken, weth, 1e18, uint64(block.timestamp));
        console.log(poolToken.balanceOf(user));
        console.log(weth.balanceOf(user));
        assert(weth.balanceOf(user) >= 1e18);
        assert(poolToken.balanceOf(user) <= expectedBalance);

    }

}