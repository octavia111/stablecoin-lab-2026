// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockUSDC} from "../../src/MockUSDC.sol";
import {SimpleStablecoin} from "../../src/SimpleStablecoin.sol";
import {Vault} from "../../src/Vault.sol";

/// @title Ex2 + Ex4 — hands-on tasks: turn red into green
/// @notice Every `assertTrue(false, "TODO ...")` below is a placeholder. Write the real
///         assertion, watch the test go green, and that exercise is done.
///
///         Acceptance: make exercise (it should be red until you are finished)
///         Do not open test/Stablecoin.t.sol — it contains the answers. Write yours
///         first, and only look once you are stuck.
contract LoopTasksTest is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    Vault internal vault;

    address internal admin = address(this);
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        usdc = new MockUSDC();
        stable = new SimpleStablecoin(admin);
        vault = new Vault(usdc, stable);
        stable.grantRole(stable.MINTER_ROLE(), address(vault));
    }

    // ==================================================================
    // Ex2 · the decimals trap: a 6-decimal stablecoin meets 18-decimal intuition
    // ==================================================================

    /// @dev For any legitimate amount x, totalSupply() must grow by exactly x after
    ///      deposit(x). Hint: use vm.assume to rule out x == 0, and faucet alice enough
    ///      usdc first.
    function test_Ex2_DepositIncreasesSupplyByExactly(uint96 raw) public { 
        uint256 amount = uint256(raw) % 1_000_000e6; 
        vm.assume(amount != 0);

        usdc.faucet(alice, amount);

        vm.startPrank(alice);
        usdc.approve(address(vault), amount); 
        vault.deposit(amount); 
        vm.stopPrank();

        assertEq(stable.totalSupply(), amount); 
        assertEq(vault.totalCollateral(), amount); 
    }

    /// @dev Run deposit with 1000e18 instead of 1000e6, see what happens, then assert what
    ///      you observed. MockUSDC has 6 decimals — 1000e18 is one billion USDC.
    ///      There is no expected answer here; the point is that you run it yourself and
    ///      read the numbers.
    function test_Ex2_DecimalsTrap() public {
        uint256 wrong = 1000e18;             // 18 位直觉：以为这是"1000 枚"

        usdc.faucet(alice, wrong);
        vm.startPrank(alice);
        usdc.approve(address(vault), wrong);
        vault.deposit(wrong);
        vm.stopPrank();

        // 断言你观察到的事实：系统按"原始单位"记账，1e18 个单位 ÷ 1e6 = 1e15 枚
        assertEq(stable.totalSupply(), wrong);          // 1_000_000_000_000_000_000_000
        assertEq(vault.totalCollateral(), wrong);       // 等式依然成立 ✓
        // 换算成"枚"看看：supply / 1e6 = 1e15，也就是你以为的 1000 枚的 10^12 倍
    }

    // ==================================================================
    // Ex4 · permissions and pausing: where the guard is, who holds the key
    // ==================================================================

    /// @dev The attacker has no MINTER_ROLE, so calling mint directly must revert. Use
    ///      vm.expectRevert + abi.encodeWithSelector to pin down the exact error.
    function test_Ex4_Mint_RevertsForNonMinter() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                attacker,
                stable.MINTER_ROLE()
            )
        );
        vm.prank(attacker);
        stable.mint(attacker, 1000e6);
    }

    /// @dev After pause(), an ordinary transfer must revert
    function test_Ex4_Pause_BlocksTransfers() public {
        // 先让 alice 合法地拿到一些 sUSD
        usdc.faucet(alice, 1000e6);
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000e6);
        vault.deposit(1000e6);
        vm.stopPrank();

        stable.pause();   // 测试合约自己是 admin

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        stable.transfer(attacker, 100e6);
    }

    /// @dev What pause() freezes is _update, so redemption is frozen along with everything
    ///      else — why is that bad news in a real crisis?
    ///      (This is STUDENT-QUESTIONS.md B1 and B2.)
    function test_Ex4_Pause_BlocksRedeem() public {
        usdc.faucet(alice, 1000e6);

        vm.startPrank(alice);
        usdc.approve(address(vault), 1000e6);
        vault.deposit(1000e6);
        vm.stopPrank();

        stable.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vault.redeem(1000e6);
    }

    /// @dev An attacker cannot burn someone else's balance
    function test_Ex4_AttackerCannotBurnOthersBalance() public {
        usdc.faucet(alice, 1000e6);
        vm.startPrank(alice);
        usdc.approve(address(vault), 1000e6);
        vault.deposit(1000e6);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                attacker,
                stable.MINTER_ROLE()
            )
        );
        vm.prank(attacker);
        stable.burn(alice, 1000e6);

        assertEq(stable.balanceOf(alice), 1000e6);   // 余额原封不动
    }


    /// @dev ...but the vault can, because it holds MINTER_ROLE and burn() answers to that
    ///      same role. This test proves the backdoor exists; it does not justify it.

}