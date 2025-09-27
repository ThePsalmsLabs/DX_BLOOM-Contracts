// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { PermitPaymentManager } from "../../../src/PermitPaymentManager.sol";
import { BaseCommerceIntegration } from "../../../src/BaseCommerceIntegration.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { MockCommerceProtocol } from "../../mocks/MockCommerceProtocol.sol";
import { ISharedTypes } from "../../../src/interfaces/ISharedTypes.sol";
import { ISignatureTransfer } from "../../../src/interfaces/IPlatformInterfaces.sol";

/**
 * @title PermitPaymentManagerTest
 * @dev Unit tests for PermitPaymentManager contract - Payment security tests
 * @notice Tests EIP-2612 permit handling, validation, and payment execution
 */
contract PermitPaymentManagerTest is TestSetup {
    // Test contracts
    PermitPaymentManager public testPermitPaymentManager;
    BaseCommerceIntegration public testBaseCommerceIntegration;
    MockCommerceProtocol public testMockCommerceProtocol;
    MockERC20 public testToken;

    // Test data
    address testUser = address(0x1234);
    address testCreator = address(0x5678);
    address testPaymentMonitor = address(0x9ABC);
    bytes16 testIntentId = bytes16(keccak256("test-intent"));
    uint256 testDeadline = block.timestamp + 1 hours;
    uint256 testAmount = 100e6; // 100 USDC
    uint256 testCreatorAmount = 80e6; // 80 USDC
    uint256 testPlatformFee = 15e6; // 15 USDC
    uint256 testOperatorFee = 5e6; // 5 USDC

    // Mock permit2 contract (we'll use the mock commerce protocol as permit2)
    address mockPermit2Address;

    function setUp() public override {
        super.setUp();

        // Deploy fresh contracts for testing
        testToken = new MockERC20("Test Token", "TEST", 6);
        testMockCommerceProtocol = new MockCommerceProtocol();
        mockPermit2Address = address(testMockCommerceProtocol);

        // Deploy BaseCommerceIntegration (required dependency)
        testBaseCommerceIntegration = new BaseCommerceIntegration(
            address(testMockCommerceProtocol),
            address(0) // No permit2 for this test
        );

        // Deploy PermitPaymentManager
        testPermitPaymentManager = new PermitPaymentManager(
            address(testBaseCommerceIntegration),
            mockPermit2Address,
            address(testToken)
        );

        // Grant roles
        vm.prank(admin);
        testPermitPaymentManager.grantRole(testPermitPaymentManager.PAYMENT_MONITOR_ROLE(), testPaymentMonitor);

        // Mint tokens to test user
        testToken.mint(testUser, 1000e6);

        // Set up mock responses
        testMockCommerceProtocol.setEscrowPaymentSuccess(true);
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_Constructor_ValidParameters() public {
        // Test that constructor sets up correctly
        assertEq(address(testPermitPaymentManager.baseCommerceIntegration()), address(testBaseCommerceIntegration));
        assertEq(address(testPermitPaymentManager.permit2()), mockPermit2Address);
        assertEq(testPermitPaymentManager.usdcToken(), address(testToken));
        assertEq(testPermitPaymentManager.owner(), admin);

        // Test role setup
        assertTrue(testPermitPaymentManager.hasRole(testPermitPaymentManager.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(testPermitPaymentManager.hasRole(testPermitPaymentManager.PAYMENT_MONITOR_ROLE(), testPaymentMonitor));
        assertTrue(testPermitPaymentManager.hasRole(testPermitPaymentManager.PAYMENT_MONITOR_ROLE(), admin));
    }

    function test_Constructor_InvalidBaseCommerceIntegration() public {
        // Test constructor with zero base commerce integration should revert
        vm.expectRevert("Invalid base commerce integration");
        new PermitPaymentManager(address(0), mockPermit2Address, address(testToken));
    }

    function test_Constructor_InvalidPermit2() public {
        // Test constructor with zero permit2 address should revert
        vm.expectRevert("Invalid permit2 contract");
        new PermitPaymentManager(address(testBaseCommerceIntegration), address(0), address(testToken));
    }

    function test_Constructor_InvalidUSDCToken() public {
        // Test constructor with zero USDC token should revert
        vm.expectRevert("Invalid USDC token");
        new PermitPaymentManager(address(testBaseCommerceIntegration), mockPermit2Address, address(0));
    }

    // ============ PERMIT PAYMENT EXECUTION TESTS ============

    function test_ExecutePaymentWithPermit_ValidPayment() public {
        // Set up permit data
        PermitPaymentManager.Permit2Data memory permitData = _createValidPermitData();

        // Approve permit2 to spend tokens
        vm.prank(testUser);
        testToken.approve(mockPermit2Address, testAmount);

        // Execute payment with permit
        vm.prank(testUser);
        vm.expectEmit(true, true, true, true);
        emit PermitPaymentManager.PaymentExecutedWithPermit(
            testIntentId,
            testUser,
            testCreator,
            ISharedTypes.PaymentType.PayPerView,
            testAmount,
            address(testToken),
            true
        );

        bool success = testPermitPaymentManager.executePaymentWithPermit(
            testIntentId,
            testUser,
            address(testToken),
            testAmount,
            testCreator,
            ISharedTypes.PaymentType.PayPerView,
            permitData
        );

        assertTrue(success);
    }

    function test_ExecutePaymentWithPermit_UnauthorizedUser() public {
        // Non-user should not be able to execute payment
        PermitPaymentManager.Permit2Data memory permitData = _createValidPermitData();

        vm.prank(testCreator);
        vm.expectRevert("Not intent creator");
        testPermitPaymentManager.executePaymentWithPermit(
            testIntentId,
            testUser, // Different from msg.sender
            address(testToken),
            testAmount,
            testCreator,
            ISharedTypes.PaymentType.PayPerView,
            permitData
        );
    }

    function test_ExecutePaymentWithPermit_InvalidPermitData() public {
        // Test with invalid permit data
        PermitPaymentManager.Permit2Data memory permitData = _createInvalidPermitData();

        vm.prank(testUser);
        vm.expectRevert("Invalid permit data");
        testPermitPaymentManager.executePaymentWithPermit(
            testIntentId,
            testUser,
            address(testToken),
            testAmount,
            testCreator,
            ISharedTypes.PaymentType.PayPerView,
            permitData
        );
    }

    function test_ExecutePaymentWithPermit_ExpiredPermit() public {
        // Test with expired permit
        PermitPaymentManager.Permit2Data memory permitData = _createExpiredPermitData();

        vm.prank(testUser);
        vm.expectRevert("Invalid permit data");
        testPermitPaymentManager.executePaymentWithPermit(
            testIntentId,
            testUser,
            address(testToken),
            testAmount,
            testCreator,
            ISharedTypes.PaymentType.PayPerView,
            permitData
        );
    }

    function test_ExecutePaymentWithPermit_PausedContract() public {
        // Pause the contract
        vm.prank(admin);
        testPermitPaymentManager.pause();

        // Try to execute payment while paused
        PermitPaymentManager.Permit2Data memory permitData = _createValidPermitData();

        vm.prank(testUser);
        vm.expectRevert("Pausable: paused");
        testPermitPaymentManager.executePaymentWithPermit(
            testIntentId,
            testUser,
            address(testToken),
            testAmount,
            testCreator,
            ISharedTypes.PaymentType.PayPerView,
            permitData
        );
    }

    // ============ CREATE AND EXECUTE TESTS ============

    function test_CreateAndExecuteWithPermit_ValidPayment() public {
        // Set up permit data
        PermitPaymentManager.Permit2Data memory permitData = _createValidPermitData();

        // Approve permit2 to spend tokens
        vm.prank(testUser);
        testToken.approve(mockPermit2Address, testAmount);

        // Create and execute with permit
        vm.prank(testUser);
        vm.expectEmit(true, true, true, true);
        emit PermitPaymentManager.PermitPaymentCreated(
            testIntentId,
            testUser,
            testCreator,
            ISharedTypes.PaymentType.PayPerView,
            testAmount,
            address(testToken),
            0 // nonce
        );

        (bytes16 returnedIntentId, bool success) = testPermitPaymentManager.createAndExecuteWithPermit(
            testUser,
            testCreator,
            ISharedTypes.PaymentType.PayPerView,
            address(testToken),
            testAmount,
            testIntentId,
            permitData
        );

        assertEq(returnedIntentId, testIntentId);
        assertTrue(success);
    }

    function test_CreateAndExecuteWithPermit_FailedExecution() public {
        // Set up mock to fail
        testMockCommerceProtocol.setEscrowPaymentSuccess(false);

        PermitPaymentManager.Permit2Data memory permitData = _createValidPermitData();

        // Approve permit2 to spend tokens
        vm.prank(testUser);
        testToken.approve(mockPermit2Address, testAmount);

        // Create and execute with permit (should return false but not revert)
        vm.prank(testUser);
        (bytes16 returnedIntentId, bool success) = testPermitPaymentManager.createAndExecuteWithPermit(
            testUser,
            testCreator,
            ISharedTypes.PaymentType.PayPerView,
            address(testToken),
            testAmount,
            testIntentId,
            permitData
        );

        assertEq(returnedIntentId, testIntentId);
        assertFalse(success);
    }

    // ============ PERMIT VALIDATION TESTS ============

    function test_ValidatePermitData_ValidData() public {
        // Test permit data validation
        PermitPaymentManager.Permit2Data memory permitData = _createValidPermitData();

        bool isValid = testPermitPaymentManager.validatePermitData(permitData, testUser);

        assertTrue(isValid);
    }

    function test_ValidatePermitData_InvalidData() public {
        // Test permit data validation with invalid data
        PermitPaymentManager.Permit2Data memory permitData = _createInvalidPermitData();

        bool isValid = testPermitPaymentManager.validatePermitData(permitData, testUser);

        assertFalse(isValid);
    }

    function test_ValidatePermitContext_ValidContext() public {
        // Test permit context validation
        PermitPaymentManager.Permit2Data memory permitData = _createValidPermitData();

        bool isValid = testPermitPaymentManager.validatePermitContext(
            permitData,
            address(testToken),
            testAmount,
            address(testMockCommerceProtocol)
        );

        assertTrue(isValid);
    }

    function test_ValidatePermitContext_InvalidContext() public {
        // Test permit context validation with invalid context
        PermitPaymentManager.Permit2Data memory permitData = _createInvalidPermitData();

        bool isValid = testPermitPaymentManager.validatePermitContext(
            permitData,
            address(testToken),
            testAmount,
            address(testMockCommerceProtocol)
        );

        assertFalse(isValid);
    }

    // ============ CAN EXECUTE TESTS ============

    function test_CanExecuteWithPermit_ValidIntent() public {
        // Test can execute with valid intent
        PermitPaymentManager.Permit2Data memory permitData = _createValidPermitData();

        (bool canExecute, string memory reason) = testPermitPaymentManager.canExecuteWithPermit(
            testIntentId,
            testUser,
            testDeadline,
            true, // hasSignature
            permitData,
            address(testToken),
            testAmount
        );

        assertTrue(canExecute);
        assertEq(reason, "");
    }

    function test_CanExecuteWithPermit_InvalidIntent() public {
        // Test can execute with invalid intent (zero address)
        PermitPaymentManager.Permit2Data memory permitData = _createValidPermitData();

        (bool canExecute, string memory reason) = testPermitPaymentManager.canExecuteWithPermit(
            testIntentId,
            address(0), // invalid user
            testDeadline,
            true,
            permitData,
            address(testToken),
            testAmount
        );

        assertFalse(canExecute);
        assertEq(reason, "Intent not found");
    }

    function test_CanExecuteWithPermit_ExpiredIntent() public {
        // Test can execute with expired intent
        PermitPaymentManager.Permit2Data memory permitData = _createValidPermitData();

        (bool canExecute, string memory reason) = testPermitPaymentManager.canExecuteWithPermit(
            testIntentId,
            testUser,
            block.timestamp - 1, // expired deadline
            true,
            permitData,
            address(testToken),
            testAmount
        );

        assertFalse(canExecute);
        assertEq(reason, "Intent expired");
    }

    function test_CanExecuteWithPermit_NoSignature() public {
        // Test can execute without signature
        PermitPaymentManager.Permit2Data memory permitData = _createValidPermitData();

        (bool canExecute, string memory reason) = testPermitPaymentManager.canExecuteWithPermit(
            testIntentId,
            testUser,
            testDeadline,
            false, // no signature
            permitData,
            address(testToken),
            testAmount
        );

        assertFalse(canExecute);
        assertEq(reason, "No operator signature");
    }

    function test_CanExecuteWithPermit_InvalidPermitData() public {
        // Test can execute with invalid permit data
        PermitPaymentManager.Permit2Data memory permitData = _createInvalidPermitData();

        (bool canExecute, string memory reason) = testPermitPaymentManager.canExecuteWithPermit(
            testIntentId,
            testUser,
            testDeadline,
            true,
            permitData,
            address(testToken),
            testAmount
        );

        assertFalse(canExecute);
        assertEq(reason, "Invalid permit data");
    }

    function test_CanExecuteWithPermit_InvalidPermitContext() public {
        // Test can execute with invalid permit context
        PermitPaymentManager.Permit2Data memory permitData = _createInvalidPermitData();

        (bool canExecute, string memory reason) = testPermitPaymentManager.canExecuteWithPermit(
            testIntentId,
            testUser,
            testDeadline,
            true,
            permitData,
            address(testToken),
            testAmount
        );

        assertFalse(canExecute);
        assertEq(reason, "Invalid permit data");
    }

    // ============ NONCE MANAGEMENT TESTS ============

    function test_GetPermitNonce_ValidUser() public {
        // Test getting permit nonce for valid user
        uint256 nonce = testPermitPaymentManager.getPermitNonce(testUser);

        // Should return 0 for new user
        assertEq(nonce, 0);
    }

    function test_GetPermitNonce_ZeroAddress() public {
        // Test getting permit nonce for zero address
        uint256 nonce = testPermitPaymentManager.getPermitNonce(address(0));

        // Should return 0
        assertEq(nonce, 0);
    }

    // ============ DOMAIN SEPARATOR TESTS ============

    function test_GetPermitDomainSeparator() public {
        // Test getting permit domain separator
        bytes32 domainSeparator = testPermitPaymentManager.getPermitDomainSeparator();

        // Should return a valid domain separator
        assertTrue(domainSeparator != bytes32(0));
    }

    // ============ PAUSE/UNPAUSE TESTS ============

    function test_Pause_Unpause_AdminFunctions() public {
        // Test pause functionality
        vm.prank(admin);
        testPermitPaymentManager.pause();
        assertTrue(testPermitPaymentManager.paused());

        // Test unpause functionality
        vm.prank(admin);
        testPermitPaymentManager.unpause();
        assertFalse(testPermitPaymentManager.paused());
    }

    function test_Pause_UnauthorizedUser() public {
        // Non-owner should not be able to pause
        vm.prank(testUser);
        vm.expectRevert("Ownable: caller is not the owner");
        testPermitPaymentManager.pause();
    }

    function test_Unpause_UnauthorizedUser() public {
        // First pause the contract
        vm.prank(admin);
        testPermitPaymentManager.pause();

        // Non-owner should not be able to unpause
        vm.prank(testUser);
        vm.expectRevert("Ownable: caller is not the owner");
        testPermitPaymentManager.unpause();
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_GrantPaymentMonitorRole() public {
        // Grant payment monitor role
        vm.prank(admin);
        testPermitPaymentManager.grantRole(testPermitPaymentManager.PAYMENT_MONITOR_ROLE(), testUser);

        // Verify role was granted
        assertTrue(testPermitPaymentManager.hasRole(testPermitPaymentManager.PAYMENT_MONITOR_ROLE(), testUser));
    }

    function test_GrantPaymentMonitorRole_UnauthorizedUser() public {
        // Non-owner should not be able to grant roles
        vm.prank(testUser);
        vm.expectRevert("AccessControl: account 0x5000 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
        testPermitPaymentManager.grantRole(testPermitPaymentManager.PAYMENT_MONITOR_ROLE(), testUser);
    }

    // ============ EDGE CASE TESTS ============

    function test_ExecutePaymentWithPermit_ZeroAmount() public {
        // Test payment execution with zero amount
        PermitPaymentManager.Permit2Data memory permitData = _createValidPermitData();
        permitData.permit.permitted.amount = 0;

        vm.prank(testUser);
        vm.expectRevert("Invalid permit data");
        testPermitPaymentManager.executePaymentWithPermit(
            testIntentId,
            testUser,
            address(testToken),
            0, // zero amount
            testCreator,
            ISharedTypes.PaymentType.PayPerView,
            permitData
        );
    }

    function test_ExecutePaymentWithPermit_InsufficientAmount() public {
        // Test payment execution with insufficient permit amount
        PermitPaymentManager.Permit2Data memory permitData = _createValidPermitData();
        permitData.permit.permitted.amount = testAmount - 1; // Less than required

        vm.prank(testUser);
        vm.expectRevert("Invalid permit data");
        testPermitPaymentManager.executePaymentWithPermit(
            testIntentId,
            testUser,
            address(testToken),
            testAmount,
            testCreator,
            ISharedTypes.PaymentType.PayPerView,
            permitData
        );
    }

    function test_ExecutePaymentWithPermit_WrongToken() public {
        // Test payment execution with wrong token in permit
        PermitPaymentManager.Permit2Data memory permitData = _createValidPermitData();
        permitData.permit.permitted.token = address(0x1234); // Wrong token

        vm.prank(testUser);
        vm.expectRevert("Invalid permit data");
        testPermitPaymentManager.executePaymentWithPermit(
            testIntentId,
            testUser,
            address(testToken), // Correct token in payment
            testAmount,
            testCreator,
            ISharedTypes.PaymentType.PayPerView,
            permitData
        );
    }

    // ============ HELPER FUNCTIONS ============

    function _createValidPermitData() internal view returns (PermitPaymentManager.Permit2Data memory) {
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({
                token: address(testToken),
                amount: testAmount
            }),
            nonce: 0,
            deadline: testDeadline
        });

        ISignatureTransfer.SignatureTransferDetails memory transferDetails = ISignatureTransfer.SignatureTransferDetails({
            to: address(testBaseCommerceIntegration),
            requestedAmount: testAmount
        });

        return PermitPaymentManager.Permit2Data({
            permit: permit,
            transferDetails: transferDetails,
            signature: "valid_signature"
        });
    }

    function _createInvalidPermitData() internal view returns (PermitPaymentManager.Permit2Data memory) {
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({
                token: address(0), // Invalid token
                amount: 0
            }),
            nonce: 999, // Invalid nonce
            deadline: 0 // Expired
        });

        ISignatureTransfer.SignatureTransferDetails memory transferDetails = ISignatureTransfer.SignatureTransferDetails({
            to: address(0), // Invalid recipient
            requestedAmount: 0
        });

        return PermitPaymentManager.Permit2Data({
            permit: permit,
            transferDetails: transferDetails,
            signature: ""
        });
    }

    function _createExpiredPermitData() internal view returns (PermitPaymentManager.Permit2Data memory) {
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({
                token: address(testToken),
                amount: testAmount
            }),
            nonce: 0,
            deadline: block.timestamp - 1 // Expired
        });

        ISignatureTransfer.SignatureTransferDetails memory transferDetails = ISignatureTransfer.SignatureTransferDetails({
            to: address(testBaseCommerceIntegration),
            requestedAmount: testAmount
        });

        return PermitPaymentManager.Permit2Data({
            permit: permit,
            transferDetails: transferDetails,
            signature: "expired_signature"
        });
    }

    // ============ FUZZING TESTS ============

    function testFuzz_ExecutePaymentWithPermit_ValidAmounts(
        uint256 amount,
        uint256 creatorAmount,
        uint256 platformFee,
        uint256 operatorFee,
        uint256 deadline
    ) public {
        // Assume valid inputs
        vm.assume(amount > 0 && amount <= 1000e6);
        vm.assume(creatorAmount < amount);
        vm.assume(platformFee + operatorFee < amount);
        vm.assume(deadline > block.timestamp);
        vm.assume(creatorAmount + platformFee + operatorFee == amount);

        // Set up permit data
        PermitPaymentManager.Permit2Data memory permitData = _createValidPermitData();
        permitData.permit.permitted.amount = amount;
        permitData.permit.deadline = deadline;
        permitData.transferDetails.requestedAmount = amount;

        // Mint tokens to user
        testToken.mint(testUser, amount);

        // Approve permit2 to spend tokens
        vm.prank(testUser);
        testToken.approve(mockPermit2Address, amount);

        // Execute payment
        vm.prank(testUser);
        bool success = testPermitPaymentManager.executePaymentWithPermit(
            testIntentId,
            testUser,
            address(testToken),
            amount,
            testCreator,
            ISharedTypes.PaymentType.PayPerView,
            permitData
        );

        assertTrue(success);
    }

    function testFuzz_ValidatePermitData_ValidInputs(
        address user,
        uint256 nonce,
        uint256 deadline
    ) public {
        vm.assume(user != address(0));
        vm.assume(deadline > block.timestamp);

        // Create permit data
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({
                token: address(testToken),
                amount: testAmount
            }),
            nonce: nonce,
            deadline: deadline
        });

        ISignatureTransfer.SignatureTransferDetails memory transferDetails = ISignatureTransfer.SignatureTransferDetails({
            to: address(testBaseCommerceIntegration),
            requestedAmount: testAmount
        });

        PermitPaymentManager.Permit2Data memory permitData = PermitPaymentManager.Permit2Data({
            permit: permit,
            transferDetails: transferDetails,
            signature: "test_signature"
        });

        bool isValid = testPermitPaymentManager.validatePermitData(permitData, user);

        // Should be valid for non-expired deadline
        assertTrue(isValid);
    }
}
