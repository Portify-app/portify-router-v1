pragma solidity >=0.6.2;


interface IPortifyRouter {
    function WETH() external view returns (address);

    function swapExactTokensForTokens(
        uint dex_id,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapTokensForExactTokens(
        uint dex_id,
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(uint dex_id, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactETH(uint dex_id, uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint dex_id, uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapETHForExactTokens(uint dex_id, uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function getAmountOut(uint dex_id, uint amountIn, uint reserveIn, uint reserveOut) external view returns (uint amountOut);
    function getAmountIn(uint dex_id, uint amountOut, uint reserveIn, uint reserveOut) external view returns (uint amountIn);
    function getAmountsOut(uint dex_id, uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint dex_id, uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint dex_id,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint dex_id,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint dex_id,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}
