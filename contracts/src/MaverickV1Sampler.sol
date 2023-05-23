// SPDX-License-Identifier: Apache-2.0
/*

  Copyright 2020 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/

pragma solidity ^0.6;
pragma experimental ABIEncoderV2;

interface IMaverickPool {
    function tokenA() external view returns (address);
}

interface IPoolInspector {
    function calculateSwap(
        address pool,
        uint128 amount,
        bool tokenAIn,
        bool exactOutput
    ) external returns (uint256 amountOut);
}

contract MaverickV1Sampler {
    uint256 private constant CALCULATE_GAS = 300e3;

    function _calculateMaverickV1SwapWithGasEstimate(
        address pool,
        address poolInspector,
        bool tokenAIn,
        bool exactOutput,
        uint256 amount
    ) public returns (uint256 returnAmount, uint256 gasEstimate) {
        uint256 preGas = gasleft();
        try
            IPoolInspector(poolInspector).calculateSwap{gas: CALCULATE_GAS}(
                pool,
                uint128(amount),
                tokenAIn,
                exactOutput
            )
        returns (uint256 inspectorReturnAmount) {
            uint256 postGas = gasleft();
            return (inspectorReturnAmount, preGas - postGas);
        } catch (bytes memory) {}
    }

    function _maverickSampleSwaps(
        address pool,
        address poolInspector,
        bool tokenAIn,
        bool exactOutput,
        uint256[] memory amounts
    ) public returns (uint256[] memory returnAmounts, uint256[] memory gasEstimates) {
        uint256 numSamples = amounts.length;
        returnAmounts = new uint256[](numSamples);
        gasEstimates = new uint256[](numSamples);

        for (uint256 i = 0; i < numSamples - 1; ++i) {
            require(amounts[i] <= amounts[i + 1], "MaverickSampler/amountsIn must be monotonically increasing");
        }

        for (uint256 i; i < numSamples; i++) {
            (uint256 returnAmount, uint256 gasEstimate) = _calculateMaverickV1SwapWithGasEstimate(
                pool,
                poolInspector,
                tokenAIn,
                exactOutput,
                amounts[i]
            );
            if (returnAmount == 0) {
                break;
            }
            returnAmounts[i] = returnAmount;
            gasEstimates[i] = gasEstimate;
        }
    }

    function sampleSellsFromMaverickV1(
        address pool,
        address poolInspector,
        address takerToken,
        uint256[] memory takerTokenAmounts
    ) public returns (uint256[] memory makerTokenAmounts, uint256[] memory gasEstimates) {
        bool tokenAIn = IMaverickPool(pool).tokenA() == takerToken;
        (makerTokenAmounts, gasEstimates) = _maverickSampleSwaps(
            pool,
            poolInspector,
            tokenAIn,
            false,
            takerTokenAmounts
        );
    }

    function sampleBuysFromMaverickV1(
        address pool,
        address poolInspector,
        address takerToken,
        uint256[] memory makerTokenAmounts
    ) public returns (uint256[] memory takerTokenAmounts, uint256[] memory gasEstimates) {
        uint256 numSamples = makerTokenAmounts.length;
        takerTokenAmounts = new uint256[](numSamples);

        bool tokenAIn = IMaverickPool(pool).tokenA() == takerToken;
        (takerTokenAmounts, gasEstimates) = _maverickSampleSwaps(
            pool,
            poolInspector,
            tokenAIn,
            true,
            makerTokenAmounts
        );
    }
}
