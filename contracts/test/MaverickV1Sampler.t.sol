pragma solidity ^0.6;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import "../src/MaverickV1Sampler.sol";
import "../src/interfaces/IUniswapV3.sol";

contract TestMaverickV1Sampler is Test {
    // NOTE: Example test command: forge test --fork-url $ETH_RPC_URL --fork-block-number 17310550 --match-contract "Maverick"

    address constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;

    address constant FRAX_USDC_MAV_POOL = 0xccB606939387C0274AAA2426517Da315C1154e50;
    address constant DAI_USDC_MAV_POOL = 0x53dc703B78794b61281812f3a901918253BeeFee;
    address constant USDC_WETH_MAV_POOL = 0x11A653DDFBb61E0Feff5484919F06d9d254bf65F;
    address constant LUSD_WETH_MAV_POOL = 0xf4B0E6fad7443fBB7bbFEA7Dc1CBE7bf7e574b03;

    address constant poolInspector = 0x3b4a40e7a8197e2E719d416D143564a5D36B660d;

    MaverickV1Sampler sampler;
    uint256[] amountsUSDC = new uint256[](8);
    uint256[] amountsD18USD = new uint256[](8);
    uint256[] amountsWETH = new uint256[](8);

    function setUp() public {
        sampler = new MaverickV1Sampler();
        amountsUSDC[0] = 1e4;
        amountsUSDC[1] = 1e5;
        amountsUSDC[2] = 1e6;
        amountsUSDC[3] = 1e7;
        amountsUSDC[4] = 1e8;
        amountsUSDC[5] = 1e9;
        amountsUSDC[6] = 1e10;
        amountsUSDC[7] = 1e11;

        amountsD18USD[0] = 1e16;
        amountsD18USD[1] = 1e17;
        amountsD18USD[2] = 1e18;
        amountsD18USD[3] = 1e19;
        amountsD18USD[4] = 1e20;
        amountsD18USD[5] = 1e21;
        amountsD18USD[6] = 5e21;
        amountsD18USD[7] = 1e22;

        amountsWETH[0] = 1e15;
        amountsWETH[1] = 1e16;
        amountsWETH[2] = 1e17;
        amountsWETH[3] = 1e18;
        amountsWETH[4] = 1e19;
        amountsWETH[5] = 5e19;
        amountsWETH[6] = 1e20;
        amountsWETH[7] = 5e20;
    }

    function testUsdcWethSample() public {
        sampleSwaps(USDC_WETH_MAV_POOL, amountsUSDC, amountsWETH);
    }

    function testDaiUsdcSample() public {
        sampleSwaps(DAI_USDC_MAV_POOL, amountsD18USD, amountsUSDC);
    }

    function testLusdWethSample() public {
        sampleSwaps(LUSD_WETH_MAV_POOL, amountsD18USD, amountsWETH);
    }

    function testUsdcWeth() public {
        uint256 returnAmount;
        uint256 gasEstimate;
        for (uint i; i < amountsUSDC.length; i++) {
            (returnAmount, gasEstimate) = sampler.calculateSwapWithGasEstimate(
                USDC_WETH_MAV_POOL,
                poolInspector,
                true,
                false,
                amountsUSDC[i]
            );
            console2.log(returnAmount, gasEstimate);
        }
    }

    function logArrays(uint256[] memory returnAmounts, uint256[] memory gasEstimates) internal {
        for (uint i; i < returnAmounts.length; i++) {
            console2.log(returnAmounts[i], gasEstimates[i]);
        }
    }

    function sampleSwaps(address pool, uint256[] memory amountsA, uint256[] memory amountsB) public {
        uint256[] memory returnAmounts;
        uint256[] memory gasEstimates;
        console2.log("");
        console2.log("true, false");
        (returnAmounts, gasEstimates) = sampler.sampleSwaps(pool, poolInspector, true, false, amountsA);
        logArrays(returnAmounts, gasEstimates);

        console2.log("");
        console2.log("true, true");
        (returnAmounts, gasEstimates) = sampler.sampleSwaps(pool, poolInspector, true, true, amountsB);
        logArrays(returnAmounts, gasEstimates);

        console2.log("");
        console2.log("false, false");
        (returnAmounts, gasEstimates) = sampler.sampleSwaps(pool, poolInspector, false, false, amountsB);
        logArrays(returnAmounts, gasEstimates);

        console2.log("");
        console2.log("false, true");
        (returnAmounts, gasEstimates) = sampler.sampleSwaps(pool, poolInspector, false, true, amountsA);
        logArrays(returnAmounts, gasEstimates);
        console2.log("");
    }
}
