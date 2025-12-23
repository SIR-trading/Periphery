// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {QuoterMath} from "./QuoterMath.sol";
import {TickMath} from "./TickMath.sol";
import {Path} from "./Path.sol";
import {PoolAddress} from "./PoolAddress.sol";

/// @title Quoter - Uniswap V3 view-only quoter contract
/// @notice Supports quoting the calculated amounts from exact input or exact output swaps
/// @dev Updated for Solidity 0.8.x compatibility
abstract contract Quoter {
    using Path for bytes;

    // The v3 factory address
    address public immutable UNISWAP_V3_FACTORY;
    // The pool init code hash
    bytes32 public immutable POOL_INIT_CODE_HASH;

    constructor(address _factory, bytes32 _poolInitCodeHash) {
        UNISWAP_V3_FACTORY = _factory;
        POOL_INIT_CODE_HASH = _poolInitCodeHash;
    }

    function _getPool(address tokenA, address tokenB, uint24 fee) internal view returns (address pool) {
        pool = PoolAddress.computeAddress(
            UNISWAP_V3_FACTORY,
            PoolAddress.getPoolKey(tokenA, tokenB, fee),
            POOL_INIT_CODE_HASH
        );
    }

    struct QuoteExactInputSingleWithPoolParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        address pool;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Returns the amount out received for a given exact input but for a swap of a single pool
    function _quoteExactInputSingleWithPool(
        QuoteExactInputSingleWithPoolParams memory params
    )
        internal
        view
        returns (
            uint256 amountReceived,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate
        )
    {
        int256 amount0;
        int256 amount1;

        bool zeroForOne = params.tokenIn < params.tokenOut;
        IUniswapV3Pool pool = IUniswapV3Pool(params.pool);

        QuoterMath.QuoteParams memory quoteParams = QuoterMath.QuoteParams({
            zeroForOne: zeroForOne,
            fee: params.fee,
            sqrtPriceLimitX96: params.sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : params.sqrtPriceLimitX96,
            exactInput: false
        });

        (amount0, amount1, sqrtPriceX96After, initializedTicksCrossed) = QuoterMath.quote(
            pool,
            int256(params.amountIn),
            quoteParams
        );

        amountReceived = amount0 > 0 ? uint256(-amount1) : uint256(-amount0);
    }

    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Returns the amount out received for a given exact input but for a swap of a single pool
    function _quoteExactInputSingle(
        QuoteExactInputSingleParams memory params
    )
        internal
        view
        returns (
            uint256 amountReceived,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate
        )
    {
        address pool = _getPool(params.tokenIn, params.tokenOut, params.fee);

        QuoteExactInputSingleWithPoolParams memory poolParams = QuoteExactInputSingleWithPoolParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            amountIn: params.amountIn,
            fee: params.fee,
            pool: pool,
            sqrtPriceLimitX96: 0
        });

        (amountReceived, sqrtPriceX96After, initializedTicksCrossed, ) = _quoteExactInputSingleWithPool(poolParams);
    }

    /// @notice Returns the amount out received for a given exact input swap without executing the swap
    function _quoteExactInput(
        bytes memory path,
        uint256 amountIn
    )
        internal
        view
        returns (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        )
    {
        sqrtPriceX96AfterList = new uint160[](path.numPools());
        initializedTicksCrossedList = new uint32[](path.numPools());

        uint256 i = 0;
        while (true) {
            (address tokenIn, address tokenOut, uint24 fee) = path.decodeFirstPool();

            (uint256 _amountOut, uint160 _sqrtPriceX96After, uint32 initializedTicksCrossed, ) = _quoteExactInputSingle(
                QuoteExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: fee,
                    amountIn: amountIn,
                    sqrtPriceLimitX96: 0
                })
            );

            sqrtPriceX96AfterList[i] = _sqrtPriceX96After;
            initializedTicksCrossedList[i] = initializedTicksCrossed;
            amountIn = _amountOut;
            i++;

            if (path.hasMultiplePools()) {
                path = path.skipToken();
            } else {
                return (amountIn, sqrtPriceX96AfterList, initializedTicksCrossedList, 0);
            }
        }
    }

    struct QuoteExactOutputSingleWithPoolParams {
        address tokenIn;
        address tokenOut;
        uint256 amount;
        uint24 fee;
        address pool;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Returns the amount in required to receive the given exact output amount but for a swap of a single pool
    function _quoteExactOutputSingleWithPool(
        QuoteExactOutputSingleWithPoolParams memory params
    )
        internal
        view
        returns (uint256 amountIn, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)
    {
        int256 amount0;
        int256 amount1;
        uint256 amountReceived;

        bool zeroForOne = params.tokenIn < params.tokenOut;
        IUniswapV3Pool pool = IUniswapV3Pool(params.pool);

        uint256 amountOutCached = 0;
        if (params.sqrtPriceLimitX96 == 0) amountOutCached = params.amount;

        QuoterMath.QuoteParams memory quoteParams = QuoterMath.QuoteParams({
            zeroForOne: zeroForOne,
            exactInput: true, // will be overridden
            fee: params.fee,
            sqrtPriceLimitX96: params.sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : params.sqrtPriceLimitX96
        });

        (amount0, amount1, sqrtPriceX96After, initializedTicksCrossed) = QuoterMath.quote(
            pool,
            -int256(params.amount),
            quoteParams
        );

        amountIn = amount0 > 0 ? uint256(amount0) : uint256(amount1);
        amountReceived = amount0 > 0 ? uint256(-amount1) : uint256(-amount0);

        if (amountOutCached != 0) require(amountReceived == amountOutCached);
    }

    struct QuoteExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amount;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Returns the amount in required to receive the given exact output amount but for a swap of a single pool
    function _quoteExactOutputSingle(
        QuoteExactOutputSingleParams memory params
    )
        internal
        view
        returns (uint256 amountIn, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)
    {
        address pool = _getPool(params.tokenIn, params.tokenOut, params.fee);

        QuoteExactOutputSingleWithPoolParams memory poolParams = QuoteExactOutputSingleWithPoolParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            amount: params.amount,
            fee: params.fee,
            pool: pool,
            sqrtPriceLimitX96: 0
        });

        (amountIn, sqrtPriceX96After, initializedTicksCrossed, ) = _quoteExactOutputSingleWithPool(poolParams);
    }

    /// @notice Returns the amount in required for a given exact output swap without executing the swap
    function _quoteExactOutput(
        bytes memory path,
        uint256 amountOut
    )
        internal
        view
        returns (
            uint256 amountIn,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        )
    {
        sqrtPriceX96AfterList = new uint160[](path.numPools());
        initializedTicksCrossedList = new uint32[](path.numPools());

        uint256 i = 0;
        while (true) {
            (address tokenOut, address tokenIn, uint24 fee) = path.decodeFirstPool();

            (uint256 _amountIn, uint160 _sqrtPriceX96After, uint32 _initializedTicksCrossed, ) =
                _quoteExactOutputSingle(
                    QuoteExactOutputSingleParams({
                        tokenIn: tokenIn,
                        tokenOut: tokenOut,
                        amount: amountOut,
                        fee: fee,
                        sqrtPriceLimitX96: 0
                    })
                );

            sqrtPriceX96AfterList[i] = _sqrtPriceX96After;
            initializedTicksCrossedList[i] = _initializedTicksCrossed;
            amountOut = _amountIn;
            i++;

            if (path.hasMultiplePools()) {
                path = path.skipToken();
            } else {
                return (amountOut, sqrtPriceX96AfterList, initializedTicksCrossedList, 0);
            }
        }
    }
}
