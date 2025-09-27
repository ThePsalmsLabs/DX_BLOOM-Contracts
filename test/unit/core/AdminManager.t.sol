// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { AdminManager } from "../../../src/AdminManager.sol";
import { PayPerView } from "../../../src/PayPerView.sol";
import { SubscriptionManager } from "../../../src/SubscriptionManager.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";

/**
 * @title AdminManagerTest
 * @dev Unit tests for AdminManager contract
 * @notice Tests all administrative functions in isolation
 */
contract AdminManagerTest is TestSetup {
    // Test contracts
    // AdminManager is already declared in TestSetup

    // Test addresses
    address public testAuthorizedSigner = address(0x3001);
    address public testPaymentMonitor = address(0x4001);

    // Test token for fee operations
    MockERC20 public testToken;

    function setUp() public override {
        super.setUp();

        // Deploy test token
        testToken = new MockERC20("Test Token", "TEST", 18);

        // AdminManager is already deployed in TestSetup with correct parameters
        // Grant test contract the PAYMENT_MONITOR_ROLE for testing
        vm.prank(admin);
        adminManager.grantPaymentMonitorRole(address(this));
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_Constructor_ValidParameters() public {
        // Test that constructor sets up correctly
        assertEq(adminManager.owner(), admin);
        assertTrue(adminManager.hasRole(adminManager.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(adminManager.operatorFeeDestination(), operatorFeeDestination);
        assertEq(adminManager.operatorSigner(), operatorSigner);
        assertEq(adminManager.operatorFeeRate(), 50); // 0.5% default
        assertFalse(adminManager.paused());
    }

    function test_Constructor_ZeroFeeDestination() public {
        vm.expectRevert("Invalid fee destination");
        new AdminManager(address(0), operatorSigner, address(0));
    }

    function test_Constructor_ZeroSigner() public {
        vm.expectRevert("Invalid operator signer");
        new AdminManager(operatorFeeDestination, address(0), address(0));
    }

    function test_Constructor_BothZero() public {
        vm.expectRevert("Invalid fee destination");
        new AdminManager(address(0), address(0), address(0));
    }

    // ============ CONTRACT MANAGEMENT TESTS ============

    function test_SetPayPerView_ValidAddress() public {
        address newPayPerView = address(0x5001);

        vm.expectEmit(true, true, false, true);
        emit AdminManager.ContractAddressUpdated("PayPerView", address(0), newPayPerView);

        vm.prank(admin);
        adminManager.setPayPerView(newPayPerView);

        assertEq(address(adminManager.payPerView()), newPayPerView);
    }

    function test_SetPayPerView_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Invalid address");
        adminManager.setPayPerView(address(0));
    }

    function test_SetPayPerView_Unauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to onlyOwner
        adminManager.setPayPerView(address(0x5001));
    }

    function test_SetSubscriptionManager_ValidAddress() public {
        address newSubscriptionManager = address(0x6001);

        vm.expectEmit(true, true, false, true);
        emit AdminManager.ContractAddressUpdated("SubscriptionManager", address(0), newSubscriptionManager);

        vm.prank(admin);
        adminManager.setSubscriptionManager(newSubscriptionManager);

        assertEq(address(adminManager.subscriptionManager()), newSubscriptionManager);
    }

    function test_SetSubscriptionManager_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Invalid address");
        adminManager.setSubscriptionManager(address(0));
    }

    function test_SetSubscriptionManager_Unauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to onlyOwner
        adminManager.setSubscriptionManager(address(0x6001));
    }

    // ============ OPERATOR MANAGEMENT TESTS ============

    function test_RegisterAsOperator() public {
        vm.expectEmit(true, true, false, true);
        emit AdminManager.OperatorRegistered(address(adminManager), operatorFeeDestination);

        vm.prank(admin);
        adminManager.registerAsOperator();

        // Verify event was emitted
        (bool registered, address feeDestination) = adminManager.getOperatorStatus();
        assertTrue(registered);
        assertEq(feeDestination, operatorFeeDestination);
    }

    function test_RegisterAsOperatorSimple() public {
        vm.expectEmit(true, true, false, true);
        emit AdminManager.OperatorRegistered(address(adminManager), operatorFeeDestination);

        vm.prank(admin);
        adminManager.registerAsOperatorSimple();
    }

    function test_UnregisterAsOperator() public {
        vm.expectEmit(true, true, false, true);
        emit AdminManager.OperatorUnregistered(address(adminManager));

        vm.prank(admin);
        adminManager.unregisterAsOperator();
    }

    function test_RegisterAsOperator_Unauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to onlyOwner
        adminManager.registerAsOperator();
    }

    // ============ FEE MANAGEMENT TESTS ============

    function test_UpdateOperatorFeeRate_ValidRate() public {
        uint256 newRate = 100; // 1%

        vm.expectEmit(true, true, false, true);
        emit AdminManager.OperatorFeeUpdated(50, newRate);

        vm.prank(admin);
        adminManager.updateOperatorFeeRate(newRate);

        assertEq(adminManager.operatorFeeRate(), newRate);
    }

    function test_UpdateOperatorFeeRate_ZeroRate() public {
        vm.prank(admin);
        adminManager.updateOperatorFeeRate(0);

        assertEq(adminManager.operatorFeeRate(), 0);
    }

    function test_UpdateOperatorFeeRate_MaxRate() public {
        vm.prank(admin);
        adminManager.updateOperatorFeeRate(500); // 5%

        assertEq(adminManager.operatorFeeRate(), 500);
    }

    function test_UpdateOperatorFeeRate_TooHigh() public {
        vm.prank(admin);
        vm.expectRevert("Fee rate too high");
        adminManager.updateOperatorFeeRate(501); // > 5%
    }

    function test_UpdateOperatorFeeRate_Unauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to onlyOwner
        adminManager.updateOperatorFeeRate(100);
    }

    function test_UpdateOperatorFeeDestination_ValidAddress() public {
        address newDestination = address(0x7001);

        vm.expectEmit(true, true, false, true);
        emit AdminManager.OperatorFeeDestinationUpdated(operatorFeeDestination, newDestination);

        vm.prank(admin);
        adminManager.updateOperatorFeeDestination(newDestination);

        assertEq(adminManager.operatorFeeDestination(), newDestination);
    }

    function test_UpdateOperatorFeeDestination_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Invalid destination");
        adminManager.updateOperatorFeeDestination(address(0));
    }

    function test_UpdateOperatorFeeDestination_Unauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to onlyOwner
        adminManager.updateOperatorFeeDestination(address(0x7001));
    }

    // ============ SIGNER MANAGEMENT TESTS ============

    function test_UpdateOperatorSigner_ValidAddress() public {
        address newSigner = address(0x8001);

        vm.expectEmit(true, true, false, true);
        emit AdminManager.OperatorSignerUpdated(operatorSigner, newSigner);

        vm.prank(admin);
        adminManager.updateOperatorSigner(newSigner);

        assertEq(adminManager.operatorSigner(), newSigner);
    }

    function test_UpdateOperatorSigner_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Invalid signer");
        adminManager.updateOperatorSigner(address(0));
    }

    function test_UpdateOperatorSigner_Unauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to onlyOwner
        adminManager.updateOperatorSigner(address(0x8001));
    }

    function test_AddAuthorizedSigner_ValidAddress() public {
        vm.expectEmit(true, true, false, true);
        emit AdminManager.AuthorizedSignerAdded(testAuthorizedSigner);

        vm.prank(admin);
        adminManager.addAuthorizedSigner(testAuthorizedSigner);

        assertTrue(adminManager.isAuthorizedSigner(testAuthorizedSigner));
    }

    function test_AddAuthorizedSigner_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Invalid signer");
        adminManager.addAuthorizedSigner(address(0));
    }

    function test_AddAuthorizedSigner_Duplicate() public {
        // Add first time
        vm.prank(admin);
        adminManager.addAuthorizedSigner(testAuthorizedSigner);

        // Add second time - should not revert but should still be true
        vm.prank(admin);
        adminManager.addAuthorizedSigner(testAuthorizedSigner);

        assertTrue(adminManager.isAuthorizedSigner(testAuthorizedSigner));
    }

    function test_AddAuthorizedSigner_Unauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to onlyOwner
        adminManager.addAuthorizedSigner(testAuthorizedSigner);
    }

    function test_RemoveAuthorizedSigner() public {
        // First add the signer
        vm.prank(admin);
        adminManager.addAuthorizedSigner(testAuthorizedSigner);

        // Then remove it
        vm.expectEmit(true, true, false, true);
        emit AdminManager.AuthorizedSignerRemoved(testAuthorizedSigner);

        vm.prank(admin);
        adminManager.removeAuthorizedSigner(testAuthorizedSigner);

        assertFalse(adminManager.isAuthorizedSigner(testAuthorizedSigner));
    }

    function test_RemoveAuthorizedSigner_NotAdded() public {
        // Remove a signer that was never added - should not revert
        vm.prank(admin);
        adminManager.removeAuthorizedSigner(testAuthorizedSigner);

        assertFalse(adminManager.isAuthorizedSigner(testAuthorizedSigner));
    }

    function test_RemoveAuthorizedSigner_Unauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to onlyOwner
        adminManager.removeAuthorizedSigner(testAuthorizedSigner);
    }

    // ============ ROLE MANAGEMENT TESTS ============

    function test_GrantPaymentMonitorRole_ValidAddress() public {
        address newMonitor = address(0x9001);

        vm.expectEmit(true, true, false, true);
        emit AdminManager.PaymentMonitorRoleGranted(newMonitor);

        vm.prank(admin);
        adminManager.grantPaymentMonitorRole(newMonitor);

        assertTrue(adminManager.hasRole(adminManager.PAYMENT_MONITOR_ROLE(), newMonitor));
    }

    function test_GrantPaymentMonitorRole_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Invalid monitor");
        adminManager.grantPaymentMonitorRole(address(0));
    }

    function test_GrantPaymentMonitorRole_Duplicate() public {
        // Grant to same address twice - should not revert
        vm.prank(admin);
        adminManager.grantPaymentMonitorRole(testPaymentMonitor);

        vm.prank(admin);
        adminManager.grantPaymentMonitorRole(testPaymentMonitor);

        assertTrue(adminManager.hasRole(adminManager.PAYMENT_MONITOR_ROLE(), testPaymentMonitor));
    }

    function test_GrantPaymentMonitorRole_Unauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to onlyOwner
        adminManager.grantPaymentMonitorRole(testPaymentMonitor);
    }

    // ============ FEE WITHDRAWAL TESTS ============

    function test_WithdrawOperatorFees_ValidParameters() public {
        // Fund the admin manager with tokens
        uint256 amount = 100e18;
        testToken.mint(address(adminManager), amount);

        vm.expectEmit(true, true, false, true);
        emit AdminManager.OperatorFeesWithdrawn(address(testToken), amount);

        vm.prank(admin);
        adminManager.withdrawOperatorFees(address(testToken), amount);

        assertEq(testToken.balanceOf(admin), amount);
        assertEq(testToken.balanceOf(address(adminManager)), 0);
    }

    function test_WithdrawOperatorFees_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Invalid token");
        adminManager.withdrawOperatorFees(address(0), 100e18);
    }

    function test_WithdrawOperatorFees_InsufficientBalance() public {
        uint256 amount = 100e18;

        // Don't mint tokens to admin manager
        vm.prank(admin);
        vm.expectRevert(); // Should revert due to insufficient balance
        adminManager.withdrawOperatorFees(address(testToken), amount);
    }

    function test_WithdrawOperatorFees_Unauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to onlyOwner
        adminManager.withdrawOperatorFees(address(testToken), 100e18);
    }

    // ============ EMERGENCY CONTROLS TESTS ============

    function test_Pause_OnlyOwner() public {
        vm.prank(admin);
        adminManager.pause();

        assertTrue(adminManager.paused());
    }

    function test_Pause_Unauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to onlyOwner
        adminManager.pause();
    }

    function test_Unpause_OnlyOwner() public {
        // First pause
        vm.prank(admin);
        adminManager.pause();

        // Then unpause
        vm.prank(admin);
        adminManager.unpause();

        assertFalse(adminManager.paused());
    }

    function test_Unpause_WhenNotPaused() public {
        vm.prank(admin);
        adminManager.unpause(); // Should not revert

        assertFalse(adminManager.paused());
    }

    function test_Unpause_Unauthorized() public {
        // First pause
        vm.prank(admin);
        adminManager.pause();

        // Try to unpause with unauthorized account
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to onlyOwner
        adminManager.unpause();
    }

    function test_EmergencyTokenRecovery_ValidParameters() public {
        // Fund the admin manager with tokens
        uint256 amount = 100e18;
        testToken.mint(address(adminManager), amount);

        vm.expectEmit(true, true, false, true);
        emit AdminManager.EmergencyTokenRecovered(address(testToken), amount);

        vm.prank(admin);
        adminManager.emergencyTokenRecovery(address(testToken), amount);

        assertEq(testToken.balanceOf(admin), amount);
        assertEq(testToken.balanceOf(address(adminManager)), 0);
    }

    function test_EmergencyTokenRecovery_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Invalid token");
        adminManager.emergencyTokenRecovery(address(0), 100e18);
    }

    function test_EmergencyTokenRecovery_InsufficientBalance() public {
        uint256 amount = 100e18;

        // Don't mint tokens to admin manager
        vm.prank(admin);
        vm.expectRevert(); // Should revert due to insufficient balance
        adminManager.emergencyTokenRecovery(address(testToken), amount);
    }

    function test_EmergencyTokenRecovery_Unauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to onlyOwner
        adminManager.emergencyTokenRecovery(address(testToken), 100e18);
    }

    // ============ VIEW FUNCTIONS TESTS ============

    function test_GetOperatorStatus() public {
        (bool registered, address feeDestination) = adminManager.getOperatorStatus();

        assertTrue(registered); // Always returns true as placeholder
        assertEq(feeDestination, operatorFeeDestination);
    }

    function test_IsAuthorizedSigner_True() public {
        // Add a signer first
        vm.prank(admin);
        adminManager.addAuthorizedSigner(testAuthorizedSigner);

        assertTrue(adminManager.isAuthorizedSigner(testAuthorizedSigner));
    }

    function test_IsAuthorizedSigner_False() public {
        assertFalse(adminManager.isAuthorizedSigner(testAuthorizedSigner));
    }

    function test_IsAuthorizedSigner_OperatorSigner() public {
        // Operator signer should not automatically be authorized
        assertFalse(adminManager.isAuthorizedSigner(operatorSigner));
    }

    function test_GetOperatorConfig() public {
        (address feeDestination, address signer, uint256 feeRate) = adminManager.getOperatorConfig();

        assertEq(feeDestination, operatorFeeDestination);
        assertEq(signer, operatorSigner);
        assertEq(feeRate, 50); // Default rate
    }

    function test_GetOperatorConfig_AfterUpdate() public {
        // Update fee rate
        vm.prank(admin);
        adminManager.updateOperatorFeeRate(200);

        // Update fee destination
        address newDestination = address(0xA001);
        vm.prank(admin);
        adminManager.updateOperatorFeeDestination(newDestination);

        // Update signer
        address newSigner = address(0xB001);
        vm.prank(admin);
        adminManager.updateOperatorSigner(newSigner);

        (address feeDestination, address signer, uint256 feeRate) = adminManager.getOperatorConfig();

        assertEq(feeDestination, newDestination);
        assertEq(signer, newSigner);
        assertEq(feeRate, 200);
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_OnlyOwnerFunctions() public {
        // Test that only owner functions revert when called by non-owner
        vm.prank(user1);
        vm.expectRevert(); // setPayPerView
        adminManager.setPayPerView(address(0x5001));

        vm.prank(user1);
        vm.expectRevert(); // setSubscriptionManager
        adminManager.setSubscriptionManager(address(0x6001));

        vm.prank(user1);
        vm.expectRevert(); // updateOperatorFeeRate
        adminManager.updateOperatorFeeRate(100);

        vm.prank(user1);
        vm.expectRevert(); // updateOperatorFeeDestination
        adminManager.updateOperatorFeeDestination(address(0x7001));

        vm.prank(user1);
        vm.expectRevert(); // updateOperatorSigner
        adminManager.updateOperatorSigner(address(0x8001));

        vm.prank(user1);
        vm.expectRevert(); // addAuthorizedSigner
        adminManager.addAuthorizedSigner(address(0x9001));

        vm.prank(user1);
        vm.expectRevert(); // removeAuthorizedSigner
        adminManager.removeAuthorizedSigner(address(0x9001));

        vm.prank(user1);
        vm.expectRevert(); // grantPaymentMonitorRole
        adminManager.grantPaymentMonitorRole(address(0xA001));

        vm.prank(user1);
        vm.expectRevert(); // withdrawOperatorFees
        adminManager.withdrawOperatorFees(address(testToken), 100e18);

        vm.prank(user1);
        vm.expectRevert(); // pause
        adminManager.pause();

        vm.prank(user1);
        vm.expectRevert(); // unpause
        adminManager.unpause();

        vm.prank(user1);
        vm.expectRevert(); // emergencyTokenRecovery
        adminManager.emergencyTokenRecovery(address(testToken), 100e18);
    }

    // ============ PAUSABLE FUNCTIONALITY TESTS ============

    function test_Pausable_WhenPaused() public {
        // Test that functions still work when paused (no functions in AdminManager are pausable)
        vm.prank(admin);
        adminManager.pause();

        // These functions should still work even when paused
        vm.prank(admin);
        adminManager.updateOperatorFeeRate(100);

        assertTrue(adminManager.paused());
        assertEq(adminManager.operatorFeeRate(), 100);
    }

    // ============ MULTIPLE OPERATIONS TESTS ============

    function test_MultipleSignerManagement() public {
        address[] memory signers = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            signers[i] = address(uint160(0x10000 + i));
        }

        // Add all signers
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(admin);
            adminManager.addAuthorizedSigner(signers[i]);
        }

        // Verify all are added
        for (uint256 i = 0; i < 5; i++) {
            assertTrue(adminManager.isAuthorizedSigner(signers[i]));
        }

        // Remove all signers
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(admin);
            adminManager.removeAuthorizedSigner(signers[i]);
        }

        // Verify all are removed
        for (uint256 i = 0; i < 5; i++) {
            assertFalse(adminManager.isAuthorizedSigner(signers[i]));
        }
    }

    function test_CompleteConfigurationWorkflow() public {
        // Start with initial configuration
        (address feeDestination, address signer, uint256 feeRate) = adminManager.getOperatorConfig();
        assertEq(feeDestination, operatorFeeDestination);
        assertEq(signer, operatorSigner);
        assertEq(feeRate, 50);

        // Update all configuration parameters
        address newFeeDestination = address(0xC001);
        address newSigner = address(0xD001);
        uint256 newFeeRate = 150; // 1.5%

        vm.prank(admin);
        adminManager.updateOperatorFeeDestination(newFeeDestination);

        vm.prank(admin);
        adminManager.updateOperatorSigner(newSigner);

        vm.prank(admin);
        adminManager.updateOperatorFeeRate(newFeeRate);

        // Verify all updates
        (feeDestination, signer, feeRate) = adminManager.getOperatorConfig();
        assertEq(feeDestination, newFeeDestination);
        assertEq(signer, newSigner);
        assertEq(feeRate, newFeeRate);

        // Add some authorized signers
        for (uint256 i = 0; i < 3; i++) {
            address authSigner = address(uint160(0xE000 + i));
            vm.prank(admin);
            adminManager.addAuthorizedSigner(authSigner);
            assertTrue(adminManager.isAuthorizedSigner(authSigner));
        }
    }
}
