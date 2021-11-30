pragma solidity ^0.8.0;


import './interfaces/IPancakeFactory.sol';
import './interfaces/IPortifyRouter.sol';
import './interfaces/IPancakeRouter02.sol';
import './interfaces/IPancakePair.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';

import './utils/Ownable.sol';

import './libraries/TransferHelper.sol';


contract PortifyRouter is IPortifyRouter, Ownable {
    struct DexInfo {
        IPancakeV2Router02 router;
        IPancakeV2Factory factory; // could be omitted on initialization
        bytes32 pair_code_hash; // could be omitted on initialization
        string name;
    }

    struct Deal {
        uint dex_id;
        address[] path;
        uint[] amounts;
    }

    event NewDex(DexInfo new_dex);
    event DexRemoval(DexInfo removed_dex);

    DexInfo[] public dex_list;
    address public immutable override WETH;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'PortifyRouter: EXPIRED');
        _;
    }

    constructor(DexInfo[] memory _dex_list, address _WETH) {
        WETH = _WETH;

        for (uint i = 0; i < dex_list.length; i++) {
            dex_list.push(_dex_list[i]);
            dex_list[i].factory = IPancakeV2Factory(dex_list[i].router.factory());
            dex_list[i].pair_code_hash = dex_list[i].factory.INIT_CODE_PAIR_HASH();
        }
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function addNewDex(DexInfo memory new_dex) external onlyOwner {
        new_dex.factory = IPancakeV2Factory(new_dex.router.factory());
        new_dex.pair_code_hash = new_dex.factory.INIT_CODE_PAIR_HASH();

        dex_list.push(new_dex);
        emit NewDex(new_dex);
    }

    function removeDex(uint256 dex_idx) external onlyOwner {
        emit DexRemoval(dex_list[dex_idx]);

        dex_list[dex_idx] = dex_list[dex_list.length - 1];
        dex_list.pop();
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint dex_id, uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? pairFor(dex_id, output, path[i + 2]) : _to;
            IPancakePair(pairFor(dex_id, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    function swapExactTokensForTokens(
        uint dex_id,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = dex_list[dex_id].router.getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'PortifyRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, pairFor(dex_id, path[0], path[1]), amounts[0]
        );
        _swap(dex_id, amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint dex_id,
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = dex_list[dex_id].router.getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, 'PortifyRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, pairFor(dex_id, path[0], path[1]), amounts[0]
        );
        _swap(dex_id, amounts, path, to);
    }

    function swapExactETHForTokens(uint dex_id, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
    returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'PortifyRouter: INVALID_PATH');
        amounts = dex_list[dex_id].router.getAmountsOut(msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'PortifyRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(pairFor(dex_id, path[0], path[1]), amounts[0]));
        _swap(dex_id, amounts, path, to);
    }

    function swapTokensForExactETH(uint dex_id, uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
    returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'PortifyRouter: INVALID_PATH');
        amounts = dex_list[dex_id].router.getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, 'PortifyRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, pairFor(dex_id, path[0], path[1]), amounts[0]
        );
        _swap(dex_id, amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(uint dex_id, uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
    returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'PortifyRouter: INVALID_PATH');
        amounts = dex_list[dex_id].router.getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'PortifyRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, pairFor(dex_id, path[0], path[1]), amounts[0]
        );
        _swap(dex_id, amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(uint dex_id, uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
    returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'PortifyRouter: INVALID_PATH');
        amounts = dex_list[dex_id].router.getAmountsIn(amountOut, path);
        require(amounts[0] <= msg.value, 'PortifyRouter: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(pairFor(dex_id, path[0], path[1]), amounts[0]));
        _swap(dex_id, amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(uint dex_id, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = sortTokens(input, output);
            IPancakePair pair = IPancakePair(pairFor(dex_id, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
                (uint reserve0, uint reserve1,) = pair.getReserves();
                (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
                amountInput = IERC20(input).balanceOf(address(pair)) - reserveInput;
                amountOutput = dex_list[dex_id].router.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? pairFor(dex_id, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint dex_id,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, pairFor(dex_id, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(dex_id, path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to) - balanceBefore >= amountOutMin,
            'PortifyRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint dex_id,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        require(path[0] == WETH, 'PortifyRouter: INVALID_PATH');
        uint amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(pairFor(dex_id, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(dex_id, path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to) - balanceBefore >= amountOutMin,
            'PortifyRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint dex_id,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == WETH, 'PortifyRouter: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, pairFor(dex_id, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(dex_id, path, address(this));
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'PortifyRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

//    function getBestDealForDex(uint dex_id, uint amount_in, address tokenA, address tokenB) public view returns (Deal memory) {
//        // first, check obvious path
//        Deal memory simple_deal;
//        simple_deal.amounts = dex_list[dex_id].router.getAmountsOut(amount_in, [tokenA, tokenB]);
//    }

    function getAmountOut(uint dex_id, uint amountIn, uint reserveIn, uint reserveOut)
    public
    view
    virtual
    override
    returns (uint amountOut)
    {
        return dex_list[dex_id].router.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint dex_id, uint amountOut, uint reserveIn, uint reserveOut)
    public
    view
    virtual
    override
    returns (uint amountIn)
    {
        return dex_list[dex_id].router.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint dex_id, uint amountIn, address[] memory path)
    public
    view
    virtual
    override
    returns (uint[] memory amounts)
    {
        return dex_list[dex_id].router.getAmountsOut(amountIn, path);
    }

    function getAmountsIn(uint dex_id, uint amountOut, address[] memory path)
    public
    view
    virtual
    override
    returns (uint[] memory amounts)
    {
        return dex_list[dex_id].router.getAmountsIn(amountOut, path);
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'PortifyLibrary: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'PortifyLibrary: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(uint dex_id, address tokenA, address tokenB) internal view returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            dex_list[dex_id].factory,
            keccak256(abi.encodePacked(token0, token1)),
            dex_list[dex_id].pair_code_hash // init code hash
        )))));
    }

}