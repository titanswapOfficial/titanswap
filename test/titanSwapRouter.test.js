const { expectRevert, time } = require('@openzeppelin/test-helpers');

const TitanSwapV1Pair = artifacts.require('TitanSwapV1Pair');
const TitanSwapV1Factory = artifacts.require('TitanSwapV1Factory');
const TitanSwapV1Router = artifacts.require('TitanSwapV1Router');
const MockERC20 = artifacts.require('MockERC20');
const TitanFeeMaker = artifacts.require('TitanFeeMaker');


contract('TitanSwapV1Router',([deployer, alice,bob, minter]) => {
    beforeEach(async () => {
        this.factory = await TitanSwapV1Factory.new(alice, {from: deployer});
        // titan 100 亿
        this.titan = await MockERC20.new('Titan','Titan','100000000000000000000',{from: minter});
        this.weth = await MockERC20.new('WETH','WETH','100000000',{from: minter});
        this.usdt = await MockERC20.new('USDT','USDT','100000000',{from: minter});
        this.token1 = await MockERC20.new('TOKEN1', 'TOKEN', '100000000', { from: minter });
        this.token2 = await MockERC20.new('TOKEN2', 'TOKEN2', '100000000', { from: minter });

        this.lp1 = await TitanSwapV1Pair.at((await this.factory.createPair(this.weth.address, this.titan.address)).logs[0].args.pair);

        this.router = await TitanSwapV1Router.new(this.factory.address,this.weth.address,{from: deployer});
        this.titanFeeMaker = await TitanFeeMaker.new(this.factory.address,this.router.address,this.titan.address,this.weth.address,this.usdt.address,{from: deployer});

        await this.factory.setFeeTo(this.titanFeeMaker.address,{from: alice});

        // transfer to bob
        await this.titan.transfer(bob,'100000000',{from: minter});
        await this.weth.transfer(bob,'1000000',{from: minter});
        // approve
        await this.weth.approve(this.router.address,'1000000000000000000000',{from: bob});
        await this.weth.approve(this.titanFeeMaker.address,'1000000000000000000000',{from: deployer});
        await this.titan.approve(this.router.address,'1000000000000000000000',{from: bob});
        await this.titan.approve(this.titanFeeMaker.address,'1000000000000000000000',{from: bob});
        // charge titan to feeMaker contract
        await this.titanFeeMaker.chargeTitan('10000',{from: bob})
    });

    // it('should add lp successfully',async () => {
    //     await this.titan.transfer(this.lp1.address,'10000',{from: minter});
    //     await this.weth.transfer(this.lp1.address,'10000',{from: minter});
    //     await this.lp1.mint(minter);
    //     const minterLpBalance = await this.lp1.balanceOf(minter).valueOf();
    //     console.log('lp balance:' + minterLpBalance);
    // });

    // it('should get 0.3% fee successfully',async () => {
    //     await this.factory.setFeeTo(this.titanFeeMaker.address,{from: alice});
    //     // add lp
    //     await this.titan.transfer(this.lp1.address,'100000',{from: minter});
    //     await this.weth.transfer(this.lp1.address,'100000',{from: minter});
    //     await this.lp1.mint(minter);
    //
    //
    //     // Fake some revenue,secondly add lp will get lp to fee address
    //     console.log('titanFeeMaker beforeLpBalance:' + await this.lp1.balanceOf(this.titanFeeMaker.address).valueOf());
    //     await this.titan.transfer(this.lp1.address, '10000', { from: minter });
    //     await this.weth.transfer(this.lp1.address, '10000', { from: minter });
    //     await this.lp1.sync();
    //     await this.titan.transfer(this.lp1.address, '10000000', { from: minter });
    //     await this.weth.transfer(this.lp1.address, '10000000', { from: minter });
    //     await this.lp1.mint(minter);
    //
    //     console.log('miner lp balance: ' + await this.lp1.balanceOf(minter));
    //     let address0 = '0x0000000000000000000000000000000000000000';
    //     console.log('address(0) lp balance: ' + await this.lp1.balanceOf(address0));
    //     console.log('lp totalSupply: ' + await this.lp1.totalSupply());
    //     console.log('titanFeeMaker afterLpBalance:' + await this.lp1.balanceOf(this.titanFeeMaker.address).valueOf());
    //     // After calling convert, it should get titan reward
    //     // await this.titanFeeMaker.convert(this.titan.address,this.weth.address,{ from: minter });
    //
    // });

    it('add titan/eth lp',async () => {
        const deadline = (await time.latest()).add(time.duration.days(4));
        // first add lp will create pair
        await this.router.addLiquidity(this.titan.address,
            this.weth.address,
            '100000',
            '1000',
            '100000',
            '1000',
            bob,
            deadline,
            {from: bob});
        // query lp balance
        let address0 = '0x0000000000000000000000000000000000000000';
        console.log('address(0) lp balance: ' + await this.lp1.balanceOf(address0));
        console.log('bob lp balance: ' + await this.lp1.balanceOf(bob));
        console.log('before swap feeMaker lp balance: ' + await this.lp1.balanceOf(this.titanFeeMaker.address));
        // Fake some revenue,secondly add lp will get lp to fee address
        await this.titan.transfer(this.lp1.address, '10000', { from: minter });
        await this.weth.transfer(this.lp1.address, '10000', { from: minter });
        await this.lp1.sync();
        // second add lp
        await this.router.addLiquidity(this.titan.address,
            this.weth.address,
            '10000',
            '100',
            '1000',
            '10',
            bob,
            deadline,
            {from: bob});
        console.log('after swap feeMaker lp balance: ' + await this.lp1.balanceOf(this.titanFeeMaker.address));

        await this.titanFeeMaker.withdrawETH(deployer,{from: deployer});

    });

    it('swapExactTokensForTokens', async () =>{
        // transfer to bob
        // await this.titan.transfer(bob,'10000',{from: minter});
        // await this.weth.transfer(bob,'10000',{from: minter});
        // // approve
        // await this.weth.approve(this.router.address,'1000000000000000000000',{from: bob});
        // await this.titan.approve(this.router.address,'1000000000000000000000',{from: bob});
        //
        // const deadline = (await time.latest()).add(time.duration.days(4));
        // console.log('before bob titan balance:' + await this.titan.balanceOf(bob));
        // console.log('before bob weth balance:' + await this.weth.balanceOf(bob));
        // await this.router.swapExactTokensForTokens('1000','100',[this.weth.address,this.titan.address],bob,deadline,{from:bob});
        // console.log('after bob titan balance:' + await this.titan.balanceOf(bob));
        // console.log('after bob weth balance:' + await this.weth.balanceOf(bob));
        // const afterLpBalance = await this.lp1.balanceOf(this.titanFeeMaker.address).valueOf();
        // console.log('titanFeeMaker afterLpBalance:' + afterLpBalance);
        // const afterLpTotalSupply = await this.lp1.totalSupply();
        // console.log('afterLpTotalSupply:' + afterLpTotalSupply);

    });


});