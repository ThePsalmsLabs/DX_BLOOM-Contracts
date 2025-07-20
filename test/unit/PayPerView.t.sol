// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {TestSetup} from "../helpers/TestSetup.sol";
import {PayPerView} from "../../src/PayPerView.sol";
import {CreatorRegistry} from "../../src/CreatorRegistry.sol";
import {ContentRegistry} from "../../src/ContentRegistry.sol";

/**
 * @title PayPerViewTest
 * @dev Comprehensive unit tests for the PayPerView contract
 * @notice This test suite covers all aspects of content purchasing including direct USDC payments,
 *         multi-token payments via Commerce Protocol, refund handling, access control, and creator
 *         earnings management. The PayPerView contract is the core monetization engine of our platform.
 *
 * We test both simple direct payments and complex multi-token payment flows to ensure users can
 * pay with any supported token while creators receive USDC. We also test edge cases like failed
 * payments, refunds, and various error conditions to ensure robust payment processing.
 */
contract PayPerViewTest is TestSetup {
    // Test content IDs that we'll use across tests
    uint256 public testContentId1;
    uint256 public testContentId2;

    // Events we'll test for proper emission
    event ContentPurchaseInitiated(
        uint256 indexed contentId,
        address indexed buyer,
        address indexed creator,
        bytes16 intentId,
        PayPerView.PaymentMethod paymentMethod,
        uint256 usdcPrice,
        uint256 expectedPaymentAmount
    );
    event ContentPurchaseCompleted(
        uint256 indexed contentId,
        address indexed buyer,
        address indexed creator,
        bytes16 intentId,
        uint256 usdcPrice,
        uint256 actualAmountPaid,
        address paymentToken
    );
    event DirectPurchaseCompleted(
        uint256 indexed contentId,
        address indexed buyer,
        address indexed creator,
        uint256 price,
        uint256 platformFee,
        uint256 creatorEarning
    );
    event PurchaseFailed(bytes16 indexed intentId, uint256 indexed contentId, address indexed user, string reason);
    event RefundProcessed(bytes16 indexed intentId, address indexed user, uint256 amount, string reason);
    event CreatorEarningsWithdrawn(address indexed creator, uint256 amount, uint256 timestamp);
    event ExternalPurchaseRecorded(
        uint256 indexed contentId,
        address indexed buyer,
        bytes16 intentId,
        uint256 usdcPrice,
        address paymentToken,
        uint256 actualAmountPaid
    );
    event ExternalRefundProcessed(
        bytes16 indexed intentId, address indexed user, uint256 indexed contentId, uint256 amount
    );

    /**
     * @dev Test setup specific to PayPerView tests
     * @notice This runs before each test to set up creators and content
     */
    function setUp() public override {
        super.setUp();

        // Register creators for testing
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));
        assertTrue(registerCreator(creator2, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 2"));

        // Register test content
        testContentId1 = registerContent(creator1, DEFAULT_CONTENT_PRICE, "Test Content 1");
        testContentId2 = registerContent(creator2, DEFAULT_CONTENT_PRICE * 2, "Test Content 2");

        // Set up mock prices for multi-token payments
        mockQuoter.setMockPrice(priceOracle.WETH(), priceOracle.USDC(), 3000, 2000e6); // 1 WETH = 2000 USDC
        mockQuoter.setMockPrice(priceOracle.USDC(), priceOracle.WETH(), 3000, 0.0005e18); // 1 USDC = 0.0005 WETH
    }

    // ============ DIRECT USDC PURCHASE TESTS ============

    /**
     * @dev Tests successful direct USDC purchase
     * @notice This is our primary happy path test - direct USDC payments should work flawlessly
     */
    function test_PurchaseContentDirect_Success() public {
        // Arrange: Set up user with USDC balance and approval
        approveUSDC(user1, address(payPerView), DEFAULT_CONTENT_PRICE);

        // Get initial balances
        uint256 initialCreatorBalance = mockUSDC.balanceOf(creator1);
        uint256 initialUserBalance = mockUSDC.balanceOf(user1);
        uint256 initialContractBalance = mockUSDC.balanceOf(address(payPerView));

        // Calculate expected amounts
        uint256 platformFee = calculatePlatformFee(DEFAULT_CONTENT_PRICE);
        uint256 creatorEarning = DEFAULT_CONTENT_PRICE - platformFee;

        // Act: Purchase content directly with USDC
        vm.startPrank(user1);

        // Expect the DirectPurchaseCompleted event
        vm.expectEmit(true, true, true, true);
        emit DirectPurchaseCompleted(
            testContentId1, user1, creator1, DEFAULT_CONTENT_PRICE, platformFee, creatorEarning
        );

        payPerView.purchaseContentDirect(testContentId1);
        vm.stopPrank();

        // Assert: Verify the purchase was successful
        assertTrue(payPerView.hasAccess(testContentId1, user1));

        // Verify balances were updated correctly
        assertEq(mockUSDC.balanceOf(user1), initialUserBalance - DEFAULT_CONTENT_PRICE);
        assertEq(mockUSDC.balanceOf(address(payPerView)), initialContractBalance + DEFAULT_CONTENT_PRICE);

        // Verify creator earnings were recorded
        (uint256 totalEarnings, uint256 withdrawable) = payPerView.getCreatorEarnings(creator1);
        assertEq(totalEarnings, creatorEarning);
        assertEq(withdrawable, creatorEarning);

        // Verify purchase details were recorded
        PayPerView.PurchaseRecord memory purchase = payPerView.getPurchaseDetails(testContentId1, user1);
        assertTrue(purchase.hasPurchased);
        assertEq(purchase.purchasePrice, DEFAULT_CONTENT_PRICE);
        assertEq(purchase.actualAmountPaid, DEFAULT_CONTENT_PRICE);
        assertEq(purchase.paymentToken, address(mockUSDC));
        assertTrue(purchase.refundEligible);

        // Verify user purchase history
        uint256[] memory userPurchases = payPerView.getUserPurchases(user1);
        assertEq(userPurchases.length, 1);
        assertEq(userPurchases[0], testContentId1);
    }

    /**
     * @dev Tests direct purchase with insufficient balance
     * @notice This tests our balance validation
     */
    function test_PurchaseContentDirect_InsufficientBalance() public {
        // Arrange: Set up user with insufficient balance
        mockUSDC.forceBalance(user1, DEFAULT_CONTENT_PRICE - 1);
        approveUSDC(user1, address(payPerView), DEFAULT_CONTENT_PRICE);

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(user1);
        vm.expectRevert("Insufficient balance");
        payPerView.purchaseContentDirect(testContentId1);
        vm.stopPrank();

        // Verify no purchase was recorded
        assertFalse(payPerView.hasAccess(testContentId1, user1));
    }

    /**
     * @dev Tests direct purchase with insufficient allowance
     * @notice This tests our allowance validation
     */
    function test_PurchaseContentDirect_InsufficientAllowance() public {
        // Arrange: Set up user with insufficient allowance
        approveUSDC(user1, address(payPerView), DEFAULT_CONTENT_PRICE - 1);

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(user1);
        vm.expectRevert("Insufficient allowance");
        payPerView.purchaseContentDirect(testContentId1);
        vm.stopPrank();

        // Verify no purchase was recorded
        assertFalse(payPerView.hasAccess(testContentId1, user1));
    }

    /**
     * @dev Tests direct purchase of inactive content
     * @notice This tests that inactive content cannot be purchased
     */
    function test_PurchaseContentDirect_InactiveContent() public {
        // Arrange: Deactivate the content
        vm.prank(creator1);
        contentRegistry.updateContent(testContentId1, 0, false);

        // Set up user with balance and approval
        approveUSDC(user1, address(payPerView), DEFAULT_CONTENT_PRICE);

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(user1);
        vm.expectRevert("Content not active");
        payPerView.purchaseContentDirect(testContentId1);
        vm.stopPrank();

        // Verify no purchase was recorded
        assertFalse(payPerView.hasAccess(testContentId1, user1));
    }

    /**
     * @dev Tests direct purchase of already purchased content
     * @notice This tests our duplicate purchase prevention
     */
    function test_PurchaseContentDirect_AlreadyPurchased() public {
        // Arrange: Purchase content first
        approveUSDC(user1, address(payPerView), DEFAULT_CONTENT_PRICE);

        vm.prank(user1);
        payPerView.purchaseContentDirect(testContentId1);

        // Set up for second purchase attempt
        approveUSDC(user1, address(payPerView), DEFAULT_CONTENT_PRICE);

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(user1);
        vm.expectRevert("Already purchased");
        payPerView.purchaseContentDirect(testContentId1);
        vm.stopPrank();

        // Verify user still has access
        assertTrue(payPerView.hasAccess(testContentId1, user1));
    }

    /**
     * @dev Tests direct purchase with non-existent content
     * @notice This tests our content validation
     */
    function test_PurchaseContentDirect_NonExistentContent() public {
        // Arrange: Set up user with balance and approval
        approveUSDC(user1, address(payPerView), DEFAULT_CONTENT_PRICE);

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(user1);
        vm.expectRevert("Content not found");
        payPerView.purchaseContentDirect(999); // Non-existent content ID
        vm.stopPrank();
    }

    // ============ MULTI-TOKEN PAYMENT INTENT TESTS ============

    /**
     * @dev Tests creating payment intent with USDC
     * @notice This tests the payment intent creation for direct USDC payments
     */
    function test_CreatePurchaseIntent_USDC() public {
        // Arrange: Set up payment parameters
        PayPerView.PaymentMethod paymentMethod = PayPerView.PaymentMethod.USDC;
        address paymentToken = address(0);
        uint256 maxSlippage = 100; // 1%

        // Act: Create payment intent
        vm.startPrank(user1);

        // Expect the ContentPurchaseInitiated event
        vm.expectEmit(true, true, true, false);
        emit ContentPurchaseInitiated(
            testContentId1, user1, creator1, bytes16(0), paymentMethod, DEFAULT_CONTENT_PRICE, DEFAULT_CONTENT_PRICE
        );

        (bytes16 intentId, uint256 expectedAmount, uint256 deadline) =
            payPerView.createPurchaseIntent(testContentId1, paymentMethod, paymentToken, maxSlippage);
        vm.stopPrank();

        // Assert: Verify intent was created correctly
        assertTrue(intentId != 0);
        assertEq(expectedAmount, DEFAULT_CONTENT_PRICE);
        assertTrue(deadline > block.timestamp);
        assertTrue(deadline <= block.timestamp + 1 hours);
    }

    /**
     * @dev Tests creating payment intent with ETH
     * @notice This tests the payment intent creation for ETH payments
     */
    function test_CreatePurchaseIntent_ETH() public {
        // Arrange: Set up payment parameters
        PayPerView.PaymentMethod paymentMethod = PayPerView.PaymentMethod.ETH;
        address paymentToken = address(0);
        uint256 maxSlippage = 100; // 1%

        // Act: Create payment intent
        vm.startPrank(user1);

        (bytes16 intentId, uint256 expectedAmount, uint256 deadline) =
            payPerView.createPurchaseIntent(testContentId1, paymentMethod, paymentToken, maxSlippage);
        vm.stopPrank();

        // Assert: Verify intent was created correctly
        assertTrue(intentId != 0);

        // Expected amount should be ETH equivalent of USDC price
        // With mock price of 1 ETH = 2000 USDC, $0.10 should be 0.00005 ETH + 1% slippage
        uint256 expectedEthAmount = priceOracle.applySlippage(0.00005e18, maxSlippage);
        assertEq(expectedAmount, expectedEthAmount);

        assertTrue(deadline > block.timestamp);
    }

    /**
     * @dev Tests creating payment intent with OTHER_TOKEN
     * @notice This tests the payment intent creation for custom token payments
     */
    function test_CreatePurchaseIntent_OtherToken() public {
        // Arrange: Set up payment parameters
        PayPerView.PaymentMethod paymentMethod = PayPerView.PaymentMethod.OTHER_TOKEN;
        address paymentToken = address(0x1234); // Custom token
        uint256 maxSlippage = 200; // 2%

        // Set up mock price for custom token
        mockQuoter.setMockPrice(paymentToken, address(mockUSDC), 3000, 1e6); // 1 CUSTOM = 1 USDC

        // Act: Create payment intent
        vm.startPrank(user1);

        (bytes16 intentId, uint256 expectedAmount, uint256 deadline) =
            payPerView.createPurchaseIntent(testContentId1, paymentMethod, paymentToken, maxSlippage);
        vm.stopPrank();

        // Assert: Verify intent was created correctly
        assertTrue(intentId != 0);

        // Expected amount should be custom token equivalent + slippage
        uint256 expectedTokenAmount = priceOracle.applySlippage(0.1e18, maxSlippage); // 0.1 CUSTOM + 2% slippage
        assertEq(expectedAmount, expectedTokenAmount);
    }

    /**
     * @dev Tests creating payment intent for non-existent content
     * @notice This tests our content validation in intent creation
     */
    function test_CreatePurchaseIntent_NonExistentContent() public {
        // Act & Assert: Expect the transaction to revert
        vm.startPrank(user1);
        vm.expectRevert("Content not found");
        payPerView.createPurchaseIntent(
            999, // Non-existent content ID
            PayPerView.PaymentMethod.USDC,
            address(0),
            100
        );
        vm.stopPrank();
    }

    /**
     * @dev Tests creating payment intent for already purchased content
     * @notice This tests our duplicate purchase prevention in intent creation
     */
    function test_CreatePurchaseIntent_AlreadyPurchased() public {
        // Arrange: Purchase content first
        approveUSDC(user1, address(payPerView), DEFAULT_CONTENT_PRICE);

        vm.prank(user1);
        payPerView.purchaseContentDirect(testContentId1);

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(user1);
        vm.expectRevert("Already purchased");
        payPerView.createPurchaseIntent(testContentId1, PayPerView.PaymentMethod.USDC, address(0), 100);
        vm.stopPrank();
    }

    // ============ PAYMENT COMPLETION TESTS ============

    /**
     * @dev Tests successful payment completion
     * @notice This tests the payment completion flow after intent creation
     */
    function test_CompletePurchase_Success() public {
        // Arrange: Create payment intent first
        vm.startPrank(user1);
        (bytes16 intentId, uint256 expectedAmount,) =
            payPerView.createPurchaseIntent(testContentId1, PayPerView.PaymentMethod.USDC, address(0), 100);
        vm.stopPrank();

        // Grant payment processor role to test contract
        vm.prank(admin);
        payPerView.grantPaymentProcessorRole(address(this));

        // Calculate expected amounts
        uint256 platformFee = calculatePlatformFee(DEFAULT_CONTENT_PRICE);
        uint256 creatorEarning = DEFAULT_CONTENT_PRICE - platformFee;

        // Act: Complete the payment
        vm.expectEmit(true, true, true, true);
        emit ContentPurchaseCompleted(
            testContentId1, user1, creator1, intentId, DEFAULT_CONTENT_PRICE, expectedAmount, address(mockUSDC)
        );

        payPerView.completePurchase(intentId, expectedAmount, true, "");

        // Assert: Verify purchase was completed
        assertTrue(payPerView.hasAccess(testContentId1, user1));

        // Verify purchase details
        PayPerView.PurchaseRecord memory purchase = payPerView.getPurchaseDetails(testContentId1, user1);
        assertTrue(purchase.hasPurchased);
        assertEq(purchase.purchasePrice, DEFAULT_CONTENT_PRICE);
        assertEq(purchase.actualAmountPaid, expectedAmount);
        assertEq(purchase.intentId, intentId);

        // Verify creator earnings
        (uint256 totalEarnings, uint256 withdrawable) = payPerView.getCreatorEarnings(creator1);
        assertEq(totalEarnings, creatorEarning);
        assertEq(withdrawable, creatorEarning);
    }

    /**
     * @dev Tests payment completion with insufficient payment
     * @notice This tests our payment validation during completion
     */
    function test_CompletePurchase_InsufficientPayment() public {
        // Arrange: Create payment intent first
        vm.startPrank(user1);
        (bytes16 intentId, uint256 expectedAmount,) =
            payPerView.createPurchaseIntent(testContentId1, PayPerView.PaymentMethod.USDC, address(0), 100);
        vm.stopPrank();

        // Grant payment processor role to test contract
        vm.prank(admin);
        payPerView.grantPaymentProcessorRole(address(this));

        // Act & Assert: Try to complete with insufficient payment
        uint256 insufficientAmount = expectedAmount - 1;
        vm.expectRevert("Insufficient payment");
        payPerView.completePurchase(intentId, insufficientAmount, true, "");

        // Verify no purchase was recorded
        assertFalse(payPerView.hasAccess(testContentId1, user1));
    }

    /**
     * @dev Tests payment completion failure handling
     * @notice This tests how we handle failed payments
     */
    function test_CompletePurchase_PaymentFailed() public {
        // Arrange: Create payment intent first
        vm.startPrank(user1);
        (bytes16 intentId, uint256 expectedAmount,) =
            payPerView.createPurchaseIntent(testContentId1, PayPerView.PaymentMethod.USDC, address(0), 100);
        vm.stopPrank();

        // Grant payment processor role to test contract
        vm.prank(admin);
        payPerView.grantPaymentProcessorRole(address(this));

        // Act: Complete with failure
        vm.expectEmit(true, true, true, true);
        emit PurchaseFailed(intentId, testContentId1, user1, "Payment failed");

        payPerView.completePurchase(intentId, expectedAmount, false, "Payment failed");

        // Assert: Verify no purchase was recorded
        assertFalse(payPerView.hasAccess(testContentId1, user1));

        // Verify no creator earnings were recorded
        (uint256 totalEarnings, uint256 withdrawable) = payPerView.getCreatorEarnings(creator1);
        assertEq(totalEarnings, 0);
        assertEq(withdrawable, 0);
    }

    /**
     * @dev Tests payment completion with expired intent
     * @notice This tests our deadline validation
     */
    function test_CompletePurchase_ExpiredIntent() public {
        // Arrange: Create payment intent first
        vm.startPrank(user1);
        (bytes16 intentId, uint256 expectedAmount,) =
            payPerView.createPurchaseIntent(testContentId1, PayPerView.PaymentMethod.USDC, address(0), 100);
        vm.stopPrank();

        // Grant payment processor role to test contract
        vm.prank(admin);
        payPerView.grantPaymentProcessorRole(address(this));

        // Act: Advance time past deadline
        warpForward(2 hours);

        // Assert: Expect completion to revert
        vm.expectRevert("Purchase expired");
        payPerView.completePurchase(intentId, expectedAmount, true, "");
    }

    // ============ REFUND TESTS ============

    /**
     * @dev Tests requesting refund for recent purchase
     * @notice This tests our refund request functionality
     */
    function test_RequestRefund_Success() public {
        // Arrange: Make a purchase first
        approveUSDC(user1, address(payPerView), DEFAULT_CONTENT_PRICE);

        vm.prank(user1);
        payPerView.purchaseContentDirect(testContentId1);

        // Act: Request refund
        vm.startPrank(user1);

        payPerView.requestRefund(testContentId1, "Not satisfied with content");
        vm.stopPrank();

        // Assert: Verify refund was requested
        PayPerView.PurchaseRecord memory purchase = payPerView.getPurchaseDetails(testContentId1, user1);
        assertFalse(purchase.refundEligible); // Should no longer be eligible after requesting
    }

    /**
     * @dev Tests refund request for non-existent purchase
     * @notice This tests our purchase validation for refunds
     */
    function test_RequestRefund_NoPurchase() public {
        // Act & Assert: Try to request refund without purchase
        vm.startPrank(user1);
        vm.expectRevert("No purchase found");
        payPerView.requestRefund(testContentId1, "Test reason");
        vm.stopPrank();
    }

    /**
     * @dev Tests refund request after refund window expires
     * @notice This tests our refund deadline validation
     */
    function test_RequestRefund_WindowExpired() public {
        // Arrange: Make a purchase first
        approveUSDC(user1, address(payPerView), DEFAULT_CONTENT_PRICE);

        vm.prank(user1);
        payPerView.purchaseContentDirect(testContentId1);

        // Act: Advance time past refund window
        warpForward(25 hours); // Past 24 hour refund window

        // Assert: Expect refund request to revert
        vm.startPrank(user1);
        vm.expectRevert("Refund window expired");
        payPerView.requestRefund(testContentId1, "Too late");
        vm.stopPrank();
    }

    /**
     * @dev Tests refund request for already refunded purchase
     * @notice This tests our duplicate refund prevention
     */
    function test_RequestRefund_AlreadyRefunded() public {
        // Arrange: Make a purchase and request refund
        approveUSDC(user1, address(payPerView), DEFAULT_CONTENT_PRICE);

        vm.prank(user1);
        payPerView.purchaseContentDirect(testContentId1);

        vm.prank(user1);
        payPerView.requestRefund(testContentId1, "First refund");

        // Act & Assert: Try to request refund again
        vm.startPrank(user1);
        vm.expectRevert("Not refund eligible");
        payPerView.requestRefund(testContentId1, "Second refund");
        vm.stopPrank();
    }

    // ============ CREATOR EARNINGS TESTS ============

    /**
     * @dev Tests creator earnings withdrawal
     * @notice This tests that creators can withdraw their earnings
     */
    function test_WithdrawEarnings_Success() public {
        // Arrange: Make a purchase to generate earnings
        approveUSDC(user1, address(payPerView), DEFAULT_CONTENT_PRICE);

        vm.prank(user1);
        payPerView.purchaseContentDirect(testContentId1);

        // Fund the contract to pay out earnings
        uint256 creatorEarning = DEFAULT_CONTENT_PRICE - calculatePlatformFee(DEFAULT_CONTENT_PRICE);
        mockUSDC.mint(address(payPerView), creatorEarning);

        // Get initial creator balance
        uint256 initialCreatorBalance = mockUSDC.balanceOf(creator1);

        // Act: Withdraw earnings
        vm.startPrank(creator1);

        // Expect the CreatorEarningsWithdrawn event
        vm.expectEmit(true, false, false, true);
        emit CreatorEarningsWithdrawn(creator1, creatorEarning, block.timestamp);

        payPerView.withdrawEarnings();
        vm.stopPrank();

        // Assert: Verify earnings were withdrawn
        assertEq(mockUSDC.balanceOf(creator1), initialCreatorBalance + creatorEarning);

        // Verify earnings were reset
        (uint256 totalEarnings, uint256 withdrawable) = payPerView.getCreatorEarnings(creator1);
        assertEq(totalEarnings, creatorEarning); // Total should remain
        assertEq(withdrawable, 0); // Withdrawable should be reset
    }

    /**
     * @dev Tests earnings withdrawal with no earnings
     * @notice This tests our earnings validation
     */
    function test_WithdrawEarnings_NoEarnings() public {
        // Act & Assert: Try to withdraw with no earnings
        vm.startPrank(creator1);
        vm.expectRevert("No earnings to withdraw");
        payPerView.withdrawEarnings();
        vm.stopPrank();
    }

    // ============ PAYMENT OPTIONS TESTS ============

    /**
     * @dev Tests getting payment options for content
     * @notice This tests our payment option discovery functionality
     */
    function test_GetPaymentOptions_Success() public {
        // Act: Get payment options for content
        (PayPerView.PaymentMethod[] memory methods, uint256[] memory prices) =
            payPerView.getPaymentOptions(testContentId1);

        // Assert: Verify payment options are returned
        assertEq(methods.length, 3);
        assertEq(prices.length, 3);

        // Verify USDC option
        assertTrue(methods[0] == PayPerView.PaymentMethod.USDC);
        assertEq(prices[0], DEFAULT_CONTENT_PRICE);

        // Verify ETH option
        assertTrue(methods[1] == PayPerView.PaymentMethod.ETH);
        assertTrue(prices[1] > 0); // Should have ETH price

        // Verify WETH option
        assertTrue(methods[2] == PayPerView.PaymentMethod.WETH);
        assertEq(prices[2], prices[1]); // Should be same as ETH
    }

    /**
     * @dev Tests getting payment options for non-existent content
     * @notice This tests our content validation in payment options
     */
    function test_GetPaymentOptions_NonExistentContent() public {
        // Act & Assert: Expect the function to revert
        vm.expectRevert("Content not found");
        payPerView.getPaymentOptions(999);
    }

    // ============ EXTERNAL PURCHASE RECORDING TESTS ============

    /**
     * @dev Tests recording external purchase
     * @notice This tests our external purchase recording functionality
     */
    function test_RecordExternalPurchase_Success() public {
        // Arrange: Grant payment processor role
        vm.prank(admin);
        payPerView.grantPaymentProcessorRole(address(this));

        // Set up purchase parameters
        bytes16 intentId = bytes16(keccak256("test-intent"));
        uint256 usdcPrice = DEFAULT_CONTENT_PRICE;
        address paymentToken = address(mockUSDC);
        uint256 actualAmountPaid = DEFAULT_CONTENT_PRICE;

        // Act: Record external purchase
        vm.expectEmit(true, true, false, true);
        emit ExternalPurchaseRecorded(testContentId1, user1, intentId, usdcPrice, paymentToken, actualAmountPaid);

        payPerView.recordExternalPurchase(testContentId1, user1, intentId, usdcPrice, paymentToken, actualAmountPaid);

        // Assert: Verify purchase was recorded
        assertTrue(payPerView.hasAccess(testContentId1, user1));

        // Verify purchase details
        PayPerView.PurchaseRecord memory purchase = payPerView.getPurchaseDetails(testContentId1, user1);
        assertTrue(purchase.hasPurchased);
        assertEq(purchase.purchasePrice, usdcPrice);
        assertEq(purchase.actualAmountPaid, actualAmountPaid);
        assertEq(purchase.intentId, intentId);
        assertEq(purchase.paymentToken, paymentToken);
    }

    /**
     * @dev Tests external purchase recording for inactive content
     * @notice This tests our content validation for external purchases
     */
    function test_RecordExternalPurchase_InactiveContent() public {
        // Arrange: Deactivate content
        vm.prank(creator1);
        contentRegistry.updateContent(testContentId1, 0, false);

        // Grant payment processor role
        vm.prank(admin);
        payPerView.grantPaymentProcessorRole(address(this));

        // Act & Assert: Expect the function to revert
        vm.expectRevert("Content not active");
        payPerView.recordExternalPurchase(
            testContentId1, user1, bytes16(0), DEFAULT_CONTENT_PRICE, address(mockUSDC), DEFAULT_CONTENT_PRICE
        );
    }

    /**
     * @dev Tests external purchase recording without authorization
     * @notice This tests our access control for external purchases
     */
    function test_RecordExternalPurchase_Unauthorized() public {
        // Act & Assert: Try to record without authorization
        vm.startPrank(user1);
        vm.expectRevert(); // Should revert due to missing PAYMENT_PROCESSOR_ROLE
        payPerView.recordExternalPurchase(
            testContentId1, user1, bytes16(0), DEFAULT_CONTENT_PRICE, address(mockUSDC), DEFAULT_CONTENT_PRICE
        );
        vm.stopPrank();
    }

    // ============ EXTERNAL REFUND TESTS ============

    /**
     * @dev Tests handling external refund
     * @notice This tests our external refund handling functionality
     */
    function test_HandleExternalRefund_Success() public {
        // Arrange: Make a purchase first
        approveUSDC(user1, address(payPerView), DEFAULT_CONTENT_PRICE);

        vm.prank(user1);
        payPerView.purchaseContentDirect(testContentId1);

        // Get purchase details
        PayPerView.PurchaseRecord memory purchase = payPerView.getPurchaseDetails(testContentId1, user1);

        // Grant payment processor role
        vm.prank(admin);
        payPerView.grantPaymentProcessorRole(address(this));

        // Act: Handle external refund
        vm.expectEmit(true, true, true, true);
        emit ExternalRefundProcessed(purchase.intentId, user1, testContentId1, DEFAULT_CONTENT_PRICE);

        payPerView.handleExternalRefund(purchase.intentId, user1, testContentId1);

        // Assert: Verify refund was processed
        PayPerView.PurchaseRecord memory updatedPurchase = payPerView.getPurchaseDetails(testContentId1, user1);
        assertFalse(updatedPurchase.refundEligible);
    }

    /**
     * @dev Tests external refund for non-existent purchase
     * @notice This tests our purchase validation for external refunds
     */
    function test_HandleExternalRefund_NoPurchase() public {
        // Arrange: Grant payment processor role
        vm.prank(admin);
        payPerView.grantPaymentProcessorRole(address(this));

        // Act & Assert: Try to refund non-existent purchase
        vm.expectRevert("No purchase found");
        payPerView.handleExternalRefund(bytes16(0), user1, testContentId1);
    }

    // ============ ACCESS CONTROL TESTS ============

    /**
     * @dev Tests access control for payment processor role
     * @notice This tests our role-based access control
     */
    function test_PaymentProcessorRole_Access() public {
        // Arrange: Grant role to user1
        vm.prank(admin);
        payPerView.grantPaymentProcessorRole(user1);

        // Act & Assert: User should now be able to complete purchases
        // First create an intent
        vm.startPrank(user1);
        (bytes16 intentId, uint256 expectedAmount,) =
            payPerView.createPurchaseIntent(testContentId1, PayPerView.PaymentMethod.USDC, address(0), 100);
        vm.stopPrank();

        // Now complete it as the authorized user
        vm.prank(user1);
        payPerView.completePurchase(intentId, expectedAmount, true, "");

        // Verify purchase was successful
        assertTrue(payPerView.hasAccess(testContentId1, user1));
    }

    /**
     * @dev Tests that unauthorized users cannot complete purchases
     * @notice This tests our access control restrictions
     */
    function test_PaymentProcessorRole_Unauthorized() public {
        // Arrange: Create an intent
        vm.startPrank(user1);
        (bytes16 intentId, uint256 expectedAmount,) =
            payPerView.createPurchaseIntent(testContentId1, PayPerView.PaymentMethod.USDC, address(0), 100);
        vm.stopPrank();

        // Act & Assert: Try to complete without authorization
        vm.startPrank(user2);
        vm.expectRevert(); // Should revert due to missing PAYMENT_PROCESSOR_ROLE
        payPerView.completePurchase(intentId, expectedAmount, true, "");
        vm.stopPrank();
    }

    // ============ EDGE CASE TESTS ============

    /**
     * @dev Tests contract pause functionality
     * @notice This tests our emergency pause system
     */
    function test_PauseUnpause_Success() public {
        // Arrange: Set up user with balance
        approveUSDC(user1, address(payPerView), DEFAULT_CONTENT_PRICE);

        // Act: Pause the contract
        vm.prank(admin);
        payPerView.pause();

        // Assert: Purchases should fail when paused
        vm.startPrank(user1);
        vm.expectRevert(); // Should revert due to whenNotPaused modifier
        payPerView.purchaseContentDirect(testContentId1);
        vm.stopPrank();

        // Act: Unpause the contract
        vm.prank(admin);
        payPerView.unpause();

        // Assert: Purchases should work again
        vm.prank(user1);
        payPerView.purchaseContentDirect(testContentId1);

        assertTrue(payPerView.hasAccess(testContentId1, user1));
    }

    /**
     * @dev Tests multiple purchases by same user
     * @notice This tests our purchase tracking across multiple content
     */
    function test_MultiplePurchases_Success() public {
        // Arrange: Set up user with sufficient balance
        uint256 totalCost = DEFAULT_CONTENT_PRICE + (DEFAULT_CONTENT_PRICE * 2);
        approveUSDC(user1, address(payPerView), totalCost);

        // Act: Purchase multiple content pieces
        vm.startPrank(user1);
        payPerView.purchaseContentDirect(testContentId1);
        payPerView.purchaseContentDirect(testContentId2);
        vm.stopPrank();

        // Assert: Verify both purchases were successful
        assertTrue(payPerView.hasAccess(testContentId1, user1));
        assertTrue(payPerView.hasAccess(testContentId2, user1));

        // Verify purchase history
        uint256[] memory userPurchases = payPerView.getUserPurchases(user1);
        assertEq(userPurchases.length, 2);
        assertEq(userPurchases[0], testContentId1);
        assertEq(userPurchases[1], testContentId2);
    }

    /**
     * @dev Tests purchase tracking with different users
     * @notice This tests that purchases are properly isolated by user
     */
    function test_PurchaseIsolation_Success() public {
        // Arrange: Set up both users with balance
        approveUSDC(user1, address(payPerView), DEFAULT_CONTENT_PRICE);
        approveUSDC(user2, address(payPerView), DEFAULT_CONTENT_PRICE);

        // Act: Each user purchases the same content
        vm.prank(user1);
        payPerView.purchaseContentDirect(testContentId1);

        vm.prank(user2);
        payPerView.purchaseContentDirect(testContentId1);

        // Assert: Both users should have access
        assertTrue(payPerView.hasAccess(testContentId1, user1));
        assertTrue(payPerView.hasAccess(testContentId1, user2));

        // Verify purchase records are separate
        PayPerView.PurchaseRecord memory purchase1 = payPerView.getPurchaseDetails(testContentId1, user1);
        PayPerView.PurchaseRecord memory purchase2 = payPerView.getPurchaseDetails(testContentId1, user2);

        assertTrue(purchase1.hasPurchased);
        assertTrue(purchase2.hasPurchased);
        assertEq(purchase1.purchasePrice, DEFAULT_CONTENT_PRICE);
        assertEq(purchase2.purchasePrice, DEFAULT_CONTENT_PRICE);
    }

    /**
     * @dev Tests can purchase content check
     * @notice This tests our purchase eligibility checking
     */
    function test_CanPurchaseContent_Success() public {
        // Assert: User should be able to purchase initially
        assertTrue(payPerView.canPurchaseContent(testContentId1, user1));

        // Purchase content
        approveUSDC(user1, address(payPerView), DEFAULT_CONTENT_PRICE);
        vm.prank(user1);
        payPerView.purchaseContentDirect(testContentId1);

        // Assert: User should not be able to purchase again
        assertFalse(payPerView.canPurchaseContent(testContentId1, user1));
    }
}
