// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.23;

import { TestSetup } from "../helpers/TestSetup.sol";
import { AdminManager } from "../../src/AdminManager.sol";
import { PayPerView } from "../../src/PayPerView.sol";
import { SubscriptionManager } from "../../src/SubscriptionManager.sol";

/**
 * @title AdminManager Unit Tests
 * @dev Tests the administrative functions of the AdminManager contract
 * @notice Tests contract address management, operator registration, fee management, etc.
 */
contract AdminManagerTest is TestSetup {
    address public newFeeRecipient = address(0x9999);
    address public newOperatorSigner = address(0x8888);
    address public paymentMonitor = address(0x7777);

    function setUp() public override {
        super.setUp();

        // AdminManager is already deployed in TestSetup
        adminManager = AdminManager(commerceIntegration.adminManager());
    }

    // ============ CONTRACT MANAGEMENT TESTS ============

    function test_SetPayPerView_Success() public {
        vm.prank(admin);

        address newPayPerView = address(0x1234);
        adminManager.setPayPerView(newPayPerView);

        assertEq(address(adminManager.payPerView()), newPayPerView);
    }

    function test_SetPayPerView_RevertIfNotOwner() public {
        vm.prank(user1);

        address newPayPerView = address(0x1234);
        vm.expectRevert("Ownable: caller is not the owner");
        adminManager.setPayPerView(newPayPerView);
    }

    function test_SetPayPerView_RevertIfInvalidAddress() public {
        vm.prank(admin);

        vm.expectRevert("Invalid address");
        adminManager.setPayPerView(address(0));
    }

    function test_SetSubscriptionManager_Success() public {
        vm.prank(admin);

        address newSubscriptionManager = address(0x5678);
        adminManager.setSubscriptionManager(newSubscriptionManager);

        assertEq(address(adminManager.subscriptionManager()), newSubscriptionManager);
    }

    function test_SetSubscriptionManager_RevertIfNotOwner() public {
        vm.prank(user1);

        address newSubscriptionManager = address(0x5678);
        vm.expectRevert("Ownable: caller is not the owner");
        adminManager.setSubscriptionManager(newSubscriptionManager);
    }

    function test_SetSubscriptionManager_RevertIfInvalidAddress() public {
        vm.prank(admin);

        vm.expectRevert("Invalid address");
        adminManager.setSubscriptionManager(address(0));
    }

    // ============ OPERATOR MANAGEMENT TESTS ============

    function test_RegisterAsOperator_Success() public {
        vm.prank(admin);

        // Mock the commerce protocol registration
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("registerOperatorWithFeeDestination(address)", adminManager.operatorFeeDestination()),
            abi.encode()
        );

        adminManager.registerAsOperator();

        // Verify the call was made
        vm.expectCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("registerOperatorWithFeeDestination(address)", adminManager.operatorFeeDestination())
        );
    }

    function test_RegisterAsOperator_RevertIfNotOwner() public {
        vm.prank(user1);

        vm.expectRevert("Ownable: caller is not the owner");
        adminManager.registerAsOperator();
    }

    function test_RegisterAsOperatorSimple_Success() public {
        vm.prank(admin);

        // Mock the commerce protocol registration
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("registerOperator()"),
            abi.encode()
        );

        adminManager.registerAsOperatorSimple();

        // Verify the call was made
        vm.expectCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("registerOperator()")
        );
    }

    function test_UnregisterAsOperator_Success() public {
        vm.prank(admin);

        // Mock the commerce protocol unregistration
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("unregisterOperator()"),
            abi.encode()
        );

        adminManager.unregisterAsOperator();

        // Verify the call was made
        vm.expectCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("unregisterOperator()")
        );
    }

    // ============ FEE MANAGEMENT TESTS ============

    function test_UpdateOperatorFeeRate_Success() public {
        vm.prank(admin);

        uint256 newRate = 75; // 0.75%
        adminManager.updateOperatorFeeRate(newRate);

        assertEq(adminManager.operatorFeeRate(), newRate);
    }

    function test_UpdateOperatorFeeRate_RevertIfNotOwner() public {
        vm.prank(user1);

        uint256 newRate = 75;
        vm.expectRevert("Ownable: caller is not the owner");
        adminManager.updateOperatorFeeRate(newRate);
    }

    function test_UpdateOperatorFeeRate_RevertIfTooHigh() public {
        vm.prank(admin);

        uint256 tooHighRate = 600; // 6% - over limit
        vm.expectRevert("Fee rate too high");
        adminManager.updateOperatorFeeRate(tooHighRate);
    }

    function test_UpdateOperatorFeeDestination_Success() public {
        vm.prank(admin);

        adminManager.updateOperatorFeeDestination(newFeeRecipient);

        assertEq(adminManager.operatorFeeDestination(), newFeeRecipient);
    }

    function test_UpdateOperatorFeeDestination_RevertIfNotOwner() public {
        vm.prank(user1);

        vm.expectRevert("Ownable: caller is not the owner");
        adminManager.updateOperatorFeeDestination(newFeeRecipient);
    }

    function test_UpdateOperatorFeeDestination_RevertIfInvalidAddress() public {
        vm.prank(admin);

        vm.expectRevert("Invalid destination");
        adminManager.updateOperatorFeeDestination(address(0));
    }

    // ============ SIGNER MANAGEMENT TESTS ============

    function test_UpdateOperatorSigner_Success() public {
        vm.prank(admin);

        adminManager.updateOperatorSigner(newOperatorSigner);

        assertEq(adminManager.operatorSigner(), newOperatorSigner);
    }

    function test_UpdateOperatorSigner_RevertIfNotOwner() public {
        vm.prank(user1);

        vm.expectRevert("Ownable: caller is not the owner");
        adminManager.updateOperatorSigner(newOperatorSigner);
    }

    function test_UpdateOperatorSigner_RevertIfInvalidAddress() public {
        vm.prank(admin);

        vm.expectRevert("Invalid signer");
        adminManager.updateOperatorSigner(address(0));
    }

    // ============ ROLE MANAGEMENT TESTS ============

    function test_GrantPaymentMonitorRole_Success() public {
        vm.prank(admin);

        adminManager.grantPaymentMonitorRole(paymentMonitor);

        assertTrue(adminManager.hasRole(adminManager.PAYMENT_MONITOR_ROLE(), paymentMonitor));
    }

    function test_GrantPaymentMonitorRole_RevertIfNotOwner() public {
        vm.prank(user1);

        vm.expectRevert("Ownable: caller is not the owner");
        adminManager.grantPaymentMonitorRole(paymentMonitor);
    }

    function test_GrantPaymentMonitorRole_RevertIfInvalidAddress() public {
        vm.prank(admin);

        vm.expectRevert("Invalid monitor");
        adminManager.grantPaymentMonitorRole(address(0));
    }

    // ============ FEE WITHDRAWAL TESTS ============

    function test_WithdrawOperatorFees_Success() public {
        vm.prank(admin);

        // Mint some tokens to the admin manager for testing
        mockUSDC.mint(address(adminManager), 1000e6);

        uint256 initialBalance = mockUSDC.balanceOf(admin);
        uint256 withdrawAmount = 500e6;

        adminManager.withdrawOperatorFees(address(mockUSDC), withdrawAmount);

        assertEq(mockUSDC.balanceOf(admin), initialBalance + withdrawAmount);
    }

    function test_WithdrawOperatorFees_RevertIfNotOwner() public {
        vm.prank(user1);

        vm.expectRevert("Ownable: caller is not the owner");
        adminManager.withdrawOperatorFees(address(mockUSDC), 100);
    }

    function test_WithdrawOperatorFees_RevertIfInvalidToken() public {
        vm.prank(admin);

        vm.expectRevert("Invalid token");
        adminManager.withdrawOperatorFees(address(0), 100);
    }

    // ============ EMERGENCY CONTROLS TESTS ============

    function test_Pause_Success() public {
        vm.prank(admin);

        adminManager.pause();

        assertTrue(adminManager.paused());
    }

    function test_Pause_RevertIfNotOwner() public {
        vm.prank(user1);

        vm.expectRevert("Ownable: caller is not the owner");
        adminManager.pause();
    }

    function test_Unpause_Success() public {
        vm.prank(admin);

        adminManager.pause();
        assertTrue(adminManager.paused());

        adminManager.unpause();
        assertFalse(adminManager.paused());
    }

    function test_Unpause_RevertIfNotOwner() public {
        vm.prank(admin);
        adminManager.pause();

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        adminManager.unpause();
    }

    function test_EmergencyTokenRecovery_Success() public {
        vm.prank(admin);

        // Mint some tokens to the admin manager for testing
        mockUSDC.mint(address(adminManager), 1000e6);

        uint256 initialBalance = mockUSDC.balanceOf(admin);
        uint256 recoverAmount = 300e6;

        adminManager.emergencyTokenRecovery(address(mockUSDC), recoverAmount);

        assertEq(mockUSDC.balanceOf(admin), initialBalance + recoverAmount);
    }

    function test_EmergencyTokenRecovery_RevertIfNotOwner() public {
        vm.prank(user1);

        vm.expectRevert("Ownable: caller is not the owner");
        adminManager.emergencyTokenRecovery(address(mockUSDC), 100);
    }

    function test_EmergencyTokenRecovery_RevertIfInvalidToken() public {
        vm.prank(admin);

        vm.expectRevert("Invalid token");
        adminManager.emergencyTokenRecovery(address(0), 100);
    }

    // ============ VIEW FUNCTIONS TESTS ============

    function test_GetOperatorStatus_Success() public view {
        (bool registered, address feeDestination) = adminManager.getOperatorStatus();

        // Since we don't have a real commerce protocol, this will return false
        assertFalse(registered);
        assertEq(feeDestination, address(0));
    }

    function test_IsAuthorizedSigner_Success() public view {
        assertTrue(adminManager.isAuthorizedSigner(adminManager.operatorSigner()));
        assertFalse(adminManager.isAuthorizedSigner(address(0x9999)));
    }

    function test_GetOperatorConfig_Success() public view {
        (
            address feeDestination,
            address signer,
            uint256 feeRate
        ) = adminManager.getOperatorConfig();

        assertEq(feeDestination, adminManager.operatorFeeDestination());
        assertEq(signer, adminManager.operatorSigner());
        assertEq(feeRate, adminManager.operatorFeeRate());
    }

    // ============ INTEGRATION TESTS ============

    function test_ContractAddressManagement_FullFlow() public {
        vm.startPrank(admin);

        // Set new contract addresses
        address newPayPerView = address(0x1111);
        address newSubscriptionManager = address(0x2222);

        adminManager.setPayPerView(newPayPerView);
        adminManager.setSubscriptionManager(newSubscriptionManager);

        assertEq(address(adminManager.payPerView()), newPayPerView);
        assertEq(address(adminManager.subscriptionManager()), newSubscriptionManager);

        vm.stopPrank();
    }

    function test_FeeManagement_FullFlow() public {
        vm.startPrank(admin);

        // Update fee settings
        uint256 newRate = 100; // 1%
        address newDestination = address(0x3333);

        adminManager.updateOperatorFeeRate(newRate);
        adminManager.updateOperatorFeeDestination(newDestination);

        assertEq(adminManager.operatorFeeRate(), newRate);
        assertEq(adminManager.operatorFeeDestination(), newDestination);

        vm.stopPrank();
    }

    function test_EmergencyControls_FullFlow() public {
        vm.startPrank(admin);

        // Test pause/unpause cycle
        assertFalse(adminManager.paused());

        adminManager.pause();
        assertTrue(adminManager.paused());

        adminManager.unpause();
        assertFalse(adminManager.paused());

        // Test emergency recovery
        mockUSDC.mint(address(adminManager), 1000e6);
        uint256 initialBalance = mockUSDC.balanceOf(admin);

        adminManager.emergencyTokenRecovery(address(mockUSDC), 500e6);

        assertEq(mockUSDC.balanceOf(admin), initialBalance + 500e6);

        vm.stopPrank();
    }
}
