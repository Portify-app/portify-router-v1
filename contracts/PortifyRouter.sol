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
        IPancakeV2Factory factory;
        string name;
    }

    struct Deal {
        uint dex_id;
        address[] path;
        uint[] amounts;
    }

    event NewDex(DexInfo new_dex);
    event DexRemoval(DexInfo removed_dex);
    event NewBridgeToken(address token);
    event BridgeTokenRemoval(address removed_token);

    DexInfo[] public dex_list;
    address[] public bridge_tokens; // some popular tokens like usdt/busd
    address public override WETH;
    mapping (string => uint256) public dex_name_to_id;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'PortifyRouter: EXPIRED');
        _;
    }

    constructor(address[] memory routers, string[] memory names, address _WETH, address[] memory _bridge_tokens) {
        require (routers.length == names.length, "Bad names input");

        WETH = _WETH;
        bridge_tokens = _bridge_tokens;

        for (uint i = 0; i < routers.length; i++) {
            addNewDex(routers[i], names[i]);
        }
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function addBridgeToken(address token) external onlyOwner {
        bridge_tokens.push(token);
        emit NewBridgeToken(token);
    }

    function removeBridgeToken(uint token_idx) external onlyOwner {
        emit BridgeTokenRemoval(bridge_tokens[token_idx]);

        bridge_tokens[token_idx] = bridge_tokens[bridge_tokens.length - 1];
        bridge_tokens.pop();
    }

    function addNewDex(address router, string memory name) public onlyOwner {
        DexInfo memory _dex;
        _dex.router = IPancakeV2Router02(router);
        _dex.factory = IPancakeV2Factory(_dex.router.factory());
        _dex.name = name;

        dex_name_to_id[name] = dex_list.length;

        dex_list.push(_dex);
        emit NewDex(_dex);
    }

    function removeDex(uint256 dex_idx) external onlyOwner {
        emit DexRemoval(dex_list[dex_idx]);

        // update name indexes
        dex_name_to_id[dex_list[dex_idx].name] = 0;
        dex_name_to_id[dex_list[dex_list.length - 1].name] = dex_idx;

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

    function _getSimplePath(address tokenA, address tokenB) internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = tokenB;
        return path;
    }

    function _getBridgePath(address tokenA, address tokenB, address bridgeToken) internal pure returns (address[] memory) {
        address[] memory path = new address[](3);
        path[0] = tokenA;
        path[1] = bridgeToken;
        path[2] = tokenB;
        return path;
    }

    function _tryGetAmountsOut(uint dex_id, uint amount_in, address[] memory path) internal view returns (uint[] memory) {
        try dex_list[dex_id].router.getAmountsOut(amount_in, path) returns (uint[] memory amounts) {
            return amounts;
        } catch {}
        // return empty array
        uint[] memory empty_amounts = new uint[](path.length);
        return empty_amounts;
    }

    function getBestDealForDex(uint dex_id, uint amount_in, address tokenA, address tokenB) public view returns (Deal memory) {
        // first, check obvious path
        Deal memory best_deal;
        best_deal.path = _getSimplePath(tokenA, tokenB);
        best_deal.amounts = _tryGetAmountsOut(dex_id, amount_in, best_deal.path);
        best_deal.dex_id = dex_id;

        for (uint i = 0; i < bridge_tokens.length; i++) {
            Deal memory complex_deal;
            if (tokenA == bridge_tokens[i] || tokenB == bridge_tokens[i]) {
                continue;
            }
            complex_deal.path = _getBridgePath(tokenA, tokenB, bridge_tokens[i]);
            complex_deal.amounts = _tryGetAmountsOut(dex_id, amount_in, complex_deal.path);
            complex_deal.dex_id = dex_id;
            if (complex_deal.amounts[complex_deal.amounts.length - 1] > best_deal.amounts[best_deal.amounts.length - 1]) {
                best_deal = complex_deal;
            }
        }
        return best_deal;
    }

    function getBestDeals(uint amount_in, address tokenA, address tokenB) public view returns (Deal[] memory) {
        Deal[] memory deals = new Deal[](dex_list.length);
        for (uint i = 0; i < deals.length; i++) {
            deals[i] = getBestDealForDex(i, amount_in, tokenA, tokenB);
        }
        return deals;
    }

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
        pair = dex_list[dex_id].factory.getPair(token0, token1);
    }

}