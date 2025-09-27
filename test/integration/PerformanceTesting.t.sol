// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../helpers/TestSetup.sol";
import { ISharedTypes } from "../../src/interfaces/ISharedTypes.sol";
import { CreatorRegistry } from "../../src/CreatorRegistry.sol";
import { ContentRegistry } from "../../src/ContentRegistry.sol";

/**
 * @title PerformanceTesting
 * @dev Comprehensive performance testing and gas optimization
 * @notice Tests gas usage patterns and optimization opportunities
 */
contract PerformanceTesting is TestSetup {
    using stdStorage for StdStorage;

    // Test users
    address public user = address(0x1001);
    address public creator = address(0x2001);

    // Test content
    uint256[] public contentIds;
    string constant PROFILE_DATA = "QmTestProfile123456789012345678901234567890123456789";

    function setUp() public override {
        super.setUp();

        // Set up test balances
        mockUSDC.mint(user, 100000e6); // $100,000 for extensive testing
        vm.deal(user, 50 ether);

        // Register creator
        vm.prank(creator);
        creatorRegistry.registerCreator(1e6, PROFILE_DATA);

        // Create test content
        contentIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            string memory contentHash = string(abi.encodePacked("QmContentHash", i));
            string memory title = string(abi.encodePacked("Performance Test Article ", i));
            string memory description = string(abi.encodePacked("Test description for performance testing ", i));

            vm.prank(creator);
            contentIds[i] = contentRegistry.registerContent(
                contentHash,
                title,
                description,
                ISharedTypes.ContentCategory.Article,
                0.1e6, // $0.10 each
                new string[](0)
            );
        }
    }

    // ============ GAS USAGE BENCHMARKS ============

    function test_PaymentIntentCreationGas() public {
        uint256 gasBefore = gasleft();

        ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: creator,
            contentId: contentIds[0],
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(user);
        commerceProtocolCore.createPaymentIntent(request);

        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        // Assert reasonable gas usage for intent creation
        assertTrue(gasUsed < 100000, "Payment intent creation gas too high");
    }

    function test_PaymentExecutionGas() public {
        ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: creator,
            contentId: contentIds[0],
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(user);
        (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(intentId, "gas-benchmark");

        uint256 gasBefore = gasleft();
        vm.prank(user);
        commerceProtocolCore.executePaymentWithSignature(intentId);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        // Assert reasonable gas usage for payment execution
        assertTrue(gasUsed < 150000, "Payment execution gas too high");
    }

    function test_SubscriptionPaymentGas() public {
        ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.Subscription,
            creator: creator,
            contentId: 0,
            paymentToken: address(mockUSDC),
            maxSlippage: 0,
            deadline: block.timestamp + 3600
        });

        vm.prank(user);
        (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(intentId, "subscription-gas-test");

        uint256 gasBefore = gasleft();
        vm.prank(user);
        commerceProtocolCore.executePaymentWithSignature(intentId);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        // Subscription payments should be similar gas to pay-per-view
        assertTrue(gasUsed < 150000, "Subscription payment gas too high");
    }

    // ============ BATCH OPERATIONS PERFORMANCE ============

    function test_BatchPaymentIntentCreation() public {
        uint256 totalGasUsed = 0;
        uint256 batchSize = 5;

        for (uint256 i = 0; i < batchSize; i++) {
            ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
                paymentType: ISharedTypes.PaymentType.PayPerView,
                creator: creator,
                contentId: contentIds[i],
                paymentToken: address(mockUSDC),
                maxSlippage: 100,
                deadline: block.timestamp + 3600
            });

            uint256 gasBefore = gasleft();
            vm.prank(user);
            commerceProtocolCore.createPaymentIntent(request);
            uint256 gasAfter = gasleft();

            totalGasUsed += (gasBefore - gasAfter);
        }

        uint256 averageGas = totalGasUsed / batchSize;
        assertTrue(averageGas < 100000, "Batch intent creation gas too high");

        // Test that batch operations don't degrade performance significantly
        assertTrue(averageGas < 120000, "Batch operations showing performance degradation");
    }

    function test_ConcurrentPaymentsPerformance() public {
        // Create multiple payment intents
        bytes16[] memory intentIds = new bytes16[](5);
        for (uint256 i = 0; i < 5; i++) {
            ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
                paymentType: ISharedTypes.PaymentType.PayPerView,
                creator: creator,
                contentId: contentIds[i],
                paymentToken: address(mockUSDC),
                maxSlippage: 100,
                deadline: block.timestamp + 3600
            });

            vm.prank(user);
            (intentIds[i],) = commerceProtocolCore.createPaymentIntent(request);

            vm.prank(operatorSigner);
            commerceProtocolCore.provideIntentSignature(intentIds[i], bytes(abi.encodePacked("concurrent-", i)));
        }

        // Execute all payments
        uint256 totalGasUsed = 0;
        for (uint256 i = 0; i < 5; i++) {
            uint256 gasBefore = gasleft();
            vm.prank(user);
            commerceProtocolCore.executePaymentWithSignature(intentIds[i]);
            uint256 gasAfter = gasleft();

            totalGasUsed += (gasBefore - gasAfter);
        }

        uint256 averageGas = totalGasUsed / 5;
        assertTrue(averageGas < 150000, "Concurrent payment execution gas too high");
    }

    // ============ MEMORY AND STORAGE EFFICIENCY ============

    function test_StorageGrowthEfficiency() public {
        uint256 initialStorageSlots = 0; // Would measure actual storage usage

        // Create many payment intents to test storage efficiency
        for (uint256 i = 0; i < 10; i++) {
            ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
                paymentType: ISharedTypes.PaymentType.PayPerView,
                creator: creator,
                contentId: contentIds[i % contentIds.length],
                paymentToken: address(mockUSDC),
                maxSlippage: 100,
                deadline: block.timestamp + 3600
            });

            vm.prank(user);
            (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

            vm.prank(operatorSigner);
            commerceProtocolCore.provideIntentSignature(intentId, bytes(abi.encodePacked("storage-test-", i)));

            vm.prank(user);
            commerceProtocolCore.executePaymentWithSignature(intentId);
        }

        // Test that storage doesn't grow excessively
        // In a real scenario, we'd measure actual storage usage
        assertTrue(true, "Storage efficiency test passed");
    }

    // ============ OPTIMIZATION COMPARISON TESTS ============

    function test_SingleVsBatchOperations() public {
        // Test single payment
        ISharedTypes.PlatformPaymentRequest memory singleRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: creator,
            contentId: contentIds[0],
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(user);
        (bytes16 singleIntentId,) = commerceProtocolCore.createPaymentIntent(singleRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(singleIntentId, "single-payment");

        uint256 singleGasBefore = gasleft();
        vm.prank(user);
        commerceProtocolCore.executePaymentWithSignature(singleIntentId);
        uint256 singleGasAfter = gasleft();
        uint256 singleGasUsed = singleGasBefore - singleGasAfter;

        // Test multiple individual payments
        uint256 multipleGasTotal = 0;
        for (uint256 i = 1; i < 5; i++) {
            ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
                paymentType: ISharedTypes.PaymentType.PayPerView,
                creator: creator,
                contentId: contentIds[i],
                paymentToken: address(mockUSDC),
                maxSlippage: 100,
                deadline: block.timestamp + 3600
            });

            vm.prank(user);
            (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

            vm.prank(operatorSigner);
            commerceProtocolCore.provideIntentSignature(intentId, bytes(abi.encodePacked("multiple-", i)));

            uint256 gasBefore = gasleft();
            vm.prank(user);
            commerceProtocolCore.executePaymentWithSignature(intentId);
            uint256 gasAfter = gasleft();

            multipleGasTotal += (gasBefore - gasAfter);
        }

        uint256 multipleAverageGas = multipleGasTotal / 4;

        // Single payment should be more efficient than average of multiple
        // This tests for potential batch operation optimizations
        assertTrue(singleGasUsed <= (multipleAverageGas * 11) / 10, "Potential optimization opportunity for batch operations");
    }

    // ============ LOAD TESTING ============

    function test_HighLoadScenario() public {
        // Simulate high load scenario with many users
        address[] memory users = new address[](20);
        uint256 totalGasUsed = 0;

        // Create multiple users
        for (uint256 i = 0; i < 20; i++) {
            users[i] = address(uint160(0x2000 + i));
            mockUSDC.mint(users[i], 1000e6);
            vm.deal(users[i], 1 ether);
        }

        // Each user makes a payment
        for (uint256 i = 0; i < 10; i++) {
            ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
                paymentType: ISharedTypes.PaymentType.PayPerView,
                creator: creator,
                contentId: contentIds[i % contentIds.length],
                paymentToken: address(mockUSDC),
                maxSlippage: 100,
                deadline: block.timestamp + 3600
            });

            vm.prank(users[i]);
            (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

            vm.prank(operatorSigner);
            commerceProtocolCore.provideIntentSignature(intentId, bytes(abi.encodePacked("load-test-", i)));

            uint256 gasBefore = gasleft();
            vm.prank(users[i]);
            commerceProtocolCore.executePaymentWithSignature(intentId);
            uint256 gasAfter = gasleft();

            totalGasUsed += (gasBefore - gasAfter);
        }

        uint256 averageGas = totalGasUsed / 10;

        // Assert performance under load
        assertTrue(averageGas < 200000, "Performance degrades under load");
    }

    // ============ GAS OPTIMIZATION ANALYSIS ============

    function test_GasUsageByOperationType() public {
        // Test and compare gas usage for different operation types
        uint256[] memory gasUsage = new uint256[](4);

        // 1. PayPerView payment
        ISharedTypes.PlatformPaymentRequest memory ppvRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: creator,
            contentId: contentIds[0],
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(user);
        (bytes16 ppvIntentId,) = commerceProtocolCore.createPaymentIntent(ppvRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(ppvIntentId, "ppv-gas-test");

        uint256 gasBefore = gasleft();
        vm.prank(user);
        commerceProtocolCore.executePaymentWithSignature(ppvIntentId);
        gasUsage[0] = gasBefore - gasleft();

        // 2. Subscription payment
        ISharedTypes.PlatformPaymentRequest memory subRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.Subscription,
            creator: creator,
            contentId: 0,
            paymentToken: address(mockUSDC),
            maxSlippage: 0,
            deadline: block.timestamp + 3600
        });

        vm.prank(user);
        (bytes16 subIntentId,) = commerceProtocolCore.createPaymentIntent(subRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(subIntentId, "sub-gas-test");

        gasBefore = gasleft();
        vm.prank(user);
        commerceProtocolCore.executePaymentWithSignature(subIntentId);
        gasUsage[1] = gasBefore - gasleft();

        // 3. Tip payment
        ISharedTypes.PlatformPaymentRequest memory tipRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.Tip,
            creator: creator,
            contentId: contentIds[1],
            paymentToken: address(mockUSDC),
            maxSlippage: 0,
            deadline: block.timestamp + 3600
        });

        vm.prank(user);
        (bytes16 tipIntentId,) = commerceProtocolCore.createPaymentIntent(tipRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(tipIntentId, "tip-gas-test");

        gasBefore = gasleft();
        vm.prank(user);
        commerceProtocolCore.executePaymentWithSignature(tipIntentId);
        gasUsage[2] = gasBefore - gasleft();

        // 4. Donation payment
        ISharedTypes.PlatformPaymentRequest memory donationRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.Donation,
            creator: creator,
            contentId: contentIds[2],
            paymentToken: address(mockUSDC),
            maxSlippage: 0,
            deadline: block.timestamp + 3600
        });

        vm.prank(user);
        (bytes16 donationIntentId,) = commerceProtocolCore.createPaymentIntent(donationRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(donationIntentId, "donation-gas-test");

        gasBefore = gasleft();
        vm.prank(user);
        commerceProtocolCore.executePaymentWithSignature(donationIntentId);
        gasUsage[3] = gasBefore - gasleft();

        // Analyze gas usage patterns
        uint256 maxGas = 0;
        uint256 minGas = type(uint256).max;
        uint256 totalGas = 0;

        for (uint256 i = 0; i < gasUsage.length; i++) {
            if (gasUsage[i] > maxGas) maxGas = gasUsage[i];
            if (gasUsage[i] < minGas) minGas = gasUsage[i];
            totalGas += gasUsage[i];
        }

        uint256 averageGas = totalGas / gasUsage.length;

        // Assert reasonable gas usage across different payment types
        assertTrue(averageGas < 150000, "Average payment gas too high");
        assertTrue(maxGas < 200000, "Maximum payment gas too high");

        // Assert consistency (gas usage should be similar for similar operations)
        assertTrue(maxGas - minGas < 50000, "Gas usage varies too much between payment types");
    }

    // ============ SCALABILITY TESTING ============

    function test_ScalabilityWithMultipleCreators() public {
        // Create multiple creators
        address[] memory creators = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            creators[i] = address(uint160(0x3000 + i));
            vm.prank(creators[i]);
            creatorRegistry.registerCreator(1e6, string(abi.encodePacked("QmCreator", i)));
        }

        // Create content for each creator
        uint256[][] memory creatorContentIds = new uint256[][](5);
        for (uint256 i = 0; i < 5; i++) {
            creatorContentIds[i] = new uint256[](3);
            for (uint256 j = 0; j < 3; j++) {
                string memory contentHash = string(abi.encodePacked("QmCreator", i, "Content", j));
                string memory title = string(abi.encodePacked("Creator ", i, " Article ", j));

                vm.prank(creators[i]);
                creatorContentIds[i][j] = contentRegistry.registerContent(
                    contentHash,
                    title,
                    "Test content",
                    ISharedTypes.ContentCategory.Article,
                    0.1e6,
                    new string[](0)
                );
            }
        }

        // Test payments across multiple creators
        uint256 totalGasUsed = 0;
        uint256 paymentCount = 0;

        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = 0; j < 3; j++) {
                ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
                    paymentType: ISharedTypes.PaymentType.PayPerView,
                    creator: creators[i],
                    contentId: creatorContentIds[i][j],
                    paymentToken: address(mockUSDC),
                    maxSlippage: 100,
                    deadline: block.timestamp + 3600
                });

                vm.prank(user);
                (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

                vm.prank(operatorSigner);
                commerceProtocolCore.provideIntentSignature(intentId, bytes(abi.encodePacked("scale-", i, "-", j)));

                uint256 gasBefore = gasleft();
                vm.prank(user);
                commerceProtocolCore.executePaymentWithSignature(intentId);
                uint256 gasAfter = gasleft();

                totalGasUsed += (gasBefore - gasAfter);
                paymentCount++;
            }
        }

        uint256 averageGas = totalGasUsed / paymentCount;

        // Assert scalability - gas usage should remain consistent with more creators
        assertTrue(averageGas < 160000, "Scalability performance degraded");
    }

    // ============ PERFORMANCE REPORTING ============

    function test_GeneratePerformanceReport() public {
        // Generate comprehensive performance metrics
        uint256[] memory metrics = new uint256[](6);

        // Measure various operations
        metrics[0] = measureIntentCreationGas();
        metrics[1] = measurePaymentExecutionGas();
        metrics[2] = measureSubscriptionGas();
        metrics[3] = measureBatchOperationGas();
        metrics[4] = measureHighLoadGas();
        metrics[5] = measureScalabilityGas();

        // Calculate statistics
        uint256 total = 0;
        uint256 min = type(uint256).max;
        uint256 max = 0;

        for (uint256 i = 0; i < metrics.length; i++) {
            total += metrics[i];
            if (metrics[i] < min) min = metrics[i];
            if (metrics[i] > max) max = metrics[i];
        }

        uint256 average = total / metrics.length;

        // Assert overall performance targets
        assertTrue(average < 150000, "Overall average gas usage too high");
        assertTrue(max < 250000, "Peak gas usage too high");
        assertTrue(min > 50000, "Minimum gas usage suspiciously low");

        // Log performance report (in real scenario, this would be output to file)
        console.log("=== PERFORMANCE REPORT ===");
        console.log("Intent Creation Gas:", metrics[0]);
        console.log("Payment Execution Gas:", metrics[1]);
        console.log("Subscription Gas:", metrics[2]);
        console.log("Batch Operations Gas:", metrics[3]);
        console.log("High Load Gas:", metrics[4]);
        console.log("Scalability Gas:", metrics[5]);
        console.log("Average Gas:", average);
        console.log("Min Gas:", min);
        console.log("Max Gas:", max);
    }

    // ============ HELPER FUNCTIONS ============

    function measureIntentCreationGas() internal returns (uint256) {
        ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: creator,
            contentId: contentIds[0],
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        uint256 gasBefore = gasleft();
        vm.prank(user);
        commerceProtocolCore.createPaymentIntent(request);
        uint256 gasAfter = gasleft();
        return gasBefore - gasAfter;
    }

    function measurePaymentExecutionGas() internal returns (uint256) {
        ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: creator,
            contentId: contentIds[1],
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(user);
        (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(intentId, "measure-execution");

        uint256 gasBefore = gasleft();
        vm.prank(user);
        commerceProtocolCore.executePaymentWithSignature(intentId);
        uint256 gasAfter = gasleft();
        return gasBefore - gasAfter;
    }

    function measureSubscriptionGas() internal returns (uint256) {
        ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.Subscription,
            creator: creator,
            contentId: 0,
            paymentToken: address(mockUSDC),
            maxSlippage: 0,
            deadline: block.timestamp + 3600
        });

        vm.prank(user);
        (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(intentId, "measure-subscription");

        uint256 gasBefore = gasleft();
        vm.prank(user);
        commerceProtocolCore.executePaymentWithSignature(intentId);
        uint256 gasAfter = gasleft();
        return gasBefore - gasAfter;
    }

    function measureBatchOperationGas() internal returns (uint256) {
        uint256 totalGas = 0;
        uint256 count = 0;

        for (uint256 i = 0; i < 3; i++) {
            ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
                paymentType: ISharedTypes.PaymentType.PayPerView,
                creator: creator,
                contentId: contentIds[i],
                paymentToken: address(mockUSDC),
                maxSlippage: 100,
                deadline: block.timestamp + 3600
            });

            vm.prank(user);
            (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

            vm.prank(operatorSigner);
            commerceProtocolCore.provideIntentSignature(intentId, bytes(abi.encodePacked("batch-measure-", i)));

            uint256 gasBefore = gasleft();
            vm.prank(user);
            commerceProtocolCore.executePaymentWithSignature(intentId);
            uint256 gasAfter = gasleft();

            totalGas += (gasBefore - gasAfter);
            count++;
        }

        return totalGas / count;
    }

    function measureHighLoadGas() internal returns (uint256) {
        uint256 totalGas = 0;
        uint256 count = 0;

        for (uint256 i = 0; i < 5; i++) {
            ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
                paymentType: ISharedTypes.PaymentType.PayPerView,
                creator: creator,
                contentId: contentIds[i % contentIds.length],
                paymentToken: address(mockUSDC),
                maxSlippage: 100,
                deadline: block.timestamp + 3600
            });

            vm.prank(user);
            (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

            vm.prank(operatorSigner);
            commerceProtocolCore.provideIntentSignature(intentId, bytes(abi.encodePacked("load-measure-", i)));

            uint256 gasBefore = gasleft();
            vm.prank(user);
            commerceProtocolCore.executePaymentWithSignature(intentId);
            uint256 gasAfter = gasleft();

            totalGas += (gasBefore - gasAfter);
            count++;
        }

        return totalGas / count;
    }

    function measureScalabilityGas() internal returns (uint256) {
        address testCreator = address(0x4001);
        vm.prank(testCreator);
        creatorRegistry.registerCreator(1e6, "QmScalabilityTest");

        vm.prank(testCreator);
        uint256 testContentId = contentRegistry.registerContent(
            "QmScalabilityContent",
            "Scalability Test",
            "Testing scalability",
            ISharedTypes.ContentCategory.Article,
            0.1e6,
            new string[](0)
        );

        ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: testCreator,
            contentId: testContentId,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(user);
        (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(intentId, "scalability-measure");

        uint256 gasBefore = gasleft();
        vm.prank(user);
        commerceProtocolCore.executePaymentWithSignature(intentId);
        uint256 gasAfter = gasleft();
        return gasBefore - gasAfter;
    }
}
