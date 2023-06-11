// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
//comptroller
import "../contracts/Unitroller.sol";
import "../contracts/Comptroller.sol";
// cToken
import "../contracts/CErc20Delegator.sol";
import "../contracts/CErc20Delegate.sol";
import "../contracts/CToken.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
//interestModel
import "../contracts/WhitePaperInterestRateModel.sol";
//priceOracle
import "../contracts/SimplePriceOracle.sol";

contract SimpleCompoundTest is Test {
    ERC20 tokenA;
    CErc20Delegator cTokenA;
    CErc20Delegate delegateA;

    ERC20 tokenB;
    CErc20Delegator cTokenB;
    CErc20Delegate delegateB; 

    address user1;
    address user2;

    Comptroller unitrollerProxy;
    SimplePriceOracle priceOracle;
    WhitePaperInterestRateModel whitePaperInterestRateModel; 
    Comptroller comptroller;
    Unitroller unitroller; 

    uint256 initialBalanceA;
    uint256 initialBalanceB;


    function setUp() public {
        user1 = makeAddr("User1");
        user2 = makeAddr("User2");
        // oracle
        priceOracle = new SimplePriceOracle(); // deploy oracle contract
        // model
        whitePaperInterestRateModel = new WhitePaperInterestRateModel(0, 0);
        // unitroller & comptroller
        comptroller = new Comptroller();
        unitroller = new Unitroller();
        unitrollerProxy = Comptroller(address(unitroller));
        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);
        unitrollerProxy._setPriceOracle(priceOracle);
        // DATA
        bytes memory data = new bytes(0x00);

        // cERC20 A
        tokenA = new ERC20("TokenA", "TokenA");
        delegateA = new CErc20Delegate(); 
        cTokenA = new CErc20Delegator(
            address(tokenA),
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaperInterestRateModel)),
            1e18,
            "Compound TokenA",
            "cTokenA",
            18,
            payable(msg.sender),
            address(delegateA),
            data
        ); 



        // cERC20 B
        tokenB = new ERC20("TokenB", "TokenB");
        delegateB = new CErc20Delegate(); 
        cTokenB = new CErc20Delegator(
            address(tokenB),
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaperInterestRateModel)),
            1e18,
            "Compound TokenB",
            "cTokenB",
            18,
            payable(msg.sender),
            address(delegateB),
            data
        ); 

        unitrollerProxy._supportMarket(CToken(address(cTokenA)));
        unitrollerProxy._supportMarket(CToken(address(cTokenB)));

        priceOracle.setUnderlyingPrice(CToken(address(cTokenA)), 1);
        priceOracle.setUnderlyingPrice(CToken(address(cTokenB)), 100);


        unitrollerProxy._setCollateralFactor(CToken(address(cTokenB)), 5 * 1e17);

        // 清算 CloseFactor
        unitrollerProxy._setCloseFactor(5 * 1e17);

        initialBalanceA = 1000 * 10 ** cTokenA.decimals();
        initialBalanceB =  1000 * 10 ** cTokenB.decimals();

         // user1 initial prce
        deal(address(tokenA), user1, initialBalanceA);
        deal(address(tokenB), user1, initialBalanceB);

        // user2 initial prce
        deal(address(tokenA), user2, initialBalanceA);
        deal(address(tokenB), user2, initialBalanceB);

    }
    // User1 使用 100 顆（100 * 10^18） ERC20 去 mint 出 100 cERC20 token
    // 再用 100 cERC20 token redeem 回 100 顆 ERC20
    function test_mint_redeem () public {
        // 初始有 100 tokenA
        uint256 mintAmount = 100 * 10 ** tokenA.decimals();

        vm.startPrank(user1); 
        require(
            ERC20(tokenA).balanceOf(user1) == initialBalanceA, 
            "test_mint_redeem ERROR 1"
        );

        // mint
        tokenA.approve(address(cTokenA) , mintAmount);
        cTokenA.mint(mintAmount);
        require(
            cTokenA.balanceOf(user1) == mintAmount, 
             "test_mint_redeem ERROR 2"
        );

        // redeem
        cTokenA.redeem(mintAmount);
        require(
            tokenA.balanceOf(user1) == initialBalanceA, 
            "test_mint_redeem ERROR 3"
        );

    }

    // User1 使用 1 顆 token B 來 mint cToken
    // User1 使用 token B 作為抵押品來借出 50 顆 token A
    function test_borrow_repay () public {

        uint256 borrowAmount = 50 * 10 ** tokenA.decimals();
        uint256 mintAmount =  1 * 10 ** tokenB.decimals();
        // 預設 tokenA 10000顆 已存在於池中
        deal(address(tokenA), address(cTokenA), 10000 * 10 ** tokenA.decimals());

        vm.startPrank(user1); 
        // mint cTokenB
        tokenB.approve(address(cTokenB) , mintAmount);
        cTokenB.mint(mintAmount);
        require(
            CErc20Delegator(cTokenB).balanceOf(user1) == mintAmount,
            "test_borrow_repay ERROR 1"
        );
        // 將tokenB 加入抵押市場
        address[] memory addr = new address[](1);
        addr[0] = address(cTokenB);
        unitrollerProxy.enterMarkets(addr);
        // 借出 tokenA
        cTokenA.borrow(borrowAmount);

        require(
            tokenA.balanceOf(user1) == initialBalanceA + borrowAmount,
            "test_borrow_repay ERROR 2"
        );
        // 返還 tokenA
        tokenA.approve(address(cTokenA), borrowAmount);
        cTokenA.repayBorrow(borrowAmount);

        require(
            cTokenA.balanceOf(user1) == 0,
            "test_borrow_repay ERROR 3"
        );
        vm.stopPrank(); 
    }


    function test_continue_borrow_repay() public {
        uint256 borrowAmount = 50 * 10 ** tokenA.decimals();
        uint256 mintAmount =  1 * 10 ** tokenB.decimals();
        // 預設 tokenA 10000顆 已存在於池中
        deal(address(tokenA), address(cTokenA), 10000 * 10 ** tokenA.decimals());

        vm.startPrank(user1); 
        // mint cTokenB
        tokenB.approve(address(cTokenB) , mintAmount);
        cTokenB.mint(mintAmount);
        require(
            CErc20Delegator(cTokenB).balanceOf(user1) == mintAmount,
            "test_borrow_repay ERROR 1"
        );
        // 將tokenB 加入抵押市場
        address[] memory addr = new address[](1);
        addr[0] = address(cTokenB);
        unitrollerProxy.enterMarkets(addr);
        // 借出 tokenA
        cTokenA.borrow(borrowAmount);

        require(
            tokenA.balanceOf(user1) == initialBalanceA + borrowAmount,
            "test_borrow_repay ERROR 2"
        );
        vm.stopPrank(); 
    }

    // 延續 (3.) 的借貸場景，調整 token B 的 collateral factor，讓 User1 被 User2 清算
    function test_change_collateralFactor() public {

        // continue question3
        test_continue_borrow_repay();
        // change collateralFactor => 40%
        unitrollerProxy._setCollateralFactor(CToken(address(cTokenB)), 4 * 1e17);

        vm.startPrank(user2);
        (, , uint shortfall) = unitrollerProxy.getAccountLiquidity(user1);
        require(
            shortfall > 0 , 
            "don't have to be liquidated"
        );

        // 清算金額 
        uint amount = 25 * 10 ** tokenA.decimals();
        tokenA.approve(address(cTokenA), amount);
        cTokenA.liquidateBorrow(user1, amount, cTokenB);

        vm.stopPrank();
    }

    // 延續 (3.) 的借貸場景，調整 oracle 中 token B 的價格，讓 User1 被 User2 清算
    function test_change_oracle() public {
        // continue question3
        test_continue_borrow_repay();
        // change priceOracle => 80
        priceOracle.setUnderlyingPrice(CToken(address(cTokenB)), 80);

        vm.startPrank(user2);
        (, , uint shortfall) = unitrollerProxy.getAccountLiquidity(user1);
         require(
            shortfall > 0 , 
            "don't have to be liquidated"
        );

        // 清算金額 
        uint amount = 25 * 10 ** tokenA.decimals();
        tokenA.approve(address(cTokenA), amount);
        cTokenA.liquidateBorrow(user1, amount, cTokenB);

        vm.stopPrank();
    }
}