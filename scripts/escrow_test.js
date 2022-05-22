// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
//const {moveTime} = require("../utils/move-time");
//const {moveBlocks} = require("../utils/move-blocks");

let escrowFactory, escrowA, usdToken, stakeTokenA, escrowContract, deployer, beneficiary, payer, other;

const SECONDS_IN_A_HOUR = 3600
const SECONDS_IN_A_DAY = 86400
const SECONDS_IN_A_WEEK = 604800
const SECONDS_IN_A_YEAR = 31449600

async function main() {

    await initialSetup();

    //await normalSenario();

    //await unauthorizedAccess();

    await refundByMediator();





    console.log('Complete');

}

async function initialSetup(){
    [deployer, beneficiary, payer, other] = await hre.ethers.getSigners();
    const usdTokenContract = await hre.ethers.getContractFactory("USDToken");
    usdToken = await usdTokenContract.deploy();
    await usdToken.deployed();
    console.log("usdToken deployed to:", usdToken.address);

    const escrowFactoryContract = await hre.ethers.getContractFactory("EscrowContractFactory");
    escrowFactory = await escrowFactoryContract.deploy();
    await escrowFactory.deployed();
    console.log("escrowFactory deployed to:", escrowFactory.address);

    //TODO deploy more than one staking contract with StakeTokenB
    await escrowFactory.deploy(beneficiary.address, payer.address);
    escrowContract = await escrowFactory.escrowContractList(beneficiary.address, payer.address);
    console.log(escrowContract);
    escrowA = await hre.ethers.getContractAt("EscrowContract", escrowContract);

    //move usd token to payer for his payment
    await usdToken.transfer(payer.address, hre.ethers.utils.parseEther("100000"));
    await usdToken.connect(payer).approve(escrowA.address, hre.ethers.constants.MaxUint256);
    //await usdToken.transfer(other.address, hre.ethers.utils.parseEther("100000"));
}

async function normalSenario(){
    let amount1000 = hre.ethers.utils.parseEther("1000");
    await escrowA.connect(beneficiary).sendInvoice(usdToken.address, amount1000);
    console.log("balance of escrow contract: ", await printBalance(escrowA.address));
    await escrowA.connect(payer).depositFund();
    console.log("balance of escrow contract: ", await printBalance(escrowA.address));
    console.log("balance of beneficiary: ", await printBalance(beneficiary.address));
    await escrowA.connect(payer).acceptDeal();
    console.log("balance of escrow contract: ", await printBalance(escrowA.address));
    console.log("balance of factory contract: ", await printBalance(escrowFactory.address));
    console.log("balance of beneficiary: ", await printBalance(beneficiary.address));
}

async function unauthorizedAccess(){
    let amount1000 = hre.ethers.utils.parseEther("1000");
    await escrowA.connect(beneficiary).sendInvoice(usdToken.address, amount1000);
    console.log("balance of escrow contract: ", await printBalance(escrowA.address));
    await escrowA.connect(payer).depositFund();
    console.log("balance of escrow contract: ", await printBalance(escrowA.address));
    console.log("balance of beneficiary: ", await printBalance(beneficiary.address));
    await escrowA.connect(payer).depositFund().then(result => {
        console.log("deposit success");
    }).catch(err => {
        console.log("Only one active deal can proceed at the moment");
        //console.log(JSON.stringify(err));
    });
    await escrowFactory.connect(deployer).refundByMediator(beneficiary.address, payer.address).then(result => {
        console.log("refund success by mediator");
    }).catch(err => {
        console.log("Neither payer nor beneficiary ask to mediate a dispute");
    });
    await escrowFactory.connect(deployer).releaseByMediator(beneficiary.address, payer.address).then(result => {
        console.log("release success by mediator");
    }).catch(err => {
        console.log("Neither payer nor beneficiary ask to mediate a dispute");
    });

    await escrowA.connect(payer).acceptDeal();
    console.log("balance of escrow contract: ", await printBalance(escrowA.address));
    console.log("balance of factory contract: ", await printBalance(escrowFactory.address));
    console.log("balance of beneficiary: ", await printBalance(beneficiary.address));
    await escrowA.connect(payer).acceptDeal().then(result => {
        console.log("accept success");
    }).catch(err => {
        console.log("There must be active deal to be accepted");
    });
}

async function refundByMediator(){
    let amount1000 = hre.ethers.utils.parseEther("1000");
    await escrowA.connect(beneficiary).sendInvoice(usdToken.address, amount1000);
    console.log("balance of escrow contract: ", await printBalance(escrowA.address));
    await escrowA.connect(payer).depositFund();
    console.log("balance of escrow contract: ", await printBalance(escrowA.address));
    console.log("balance of beneficiary: ", await printBalance(beneficiary.address));
    console.log("balance of payer: ", await printBalance(payer.address));


    await escrowA.connect(payer).askArbitration();
    await escrowA.connect(beneficiary).askArbitration();
    console.log((await escrowA.activeDeals(0)).status);

    await escrowFactory.connect(deployer).refundByMediator(beneficiary.address, payer.address);
    console.log("balance of escrow contract: ", await printBalance(escrowA.address));
    console.log("balance of factory contract: ", await printBalance(escrowFactory.address));
    console.log("balance of beneficiary: ", await printBalance(beneficiary.address));
    console.log("balance of payer: ", await printBalance(payer.address));
}

async function printBalance(signer){
    let balance = await usdToken.balanceOf(signer);
    return hre.ethers.utils.formatEther(balance);
}

async function printAllowance(owner, spender){
    let allowance = await usdToken.allowance(owner, spender);
    return hre.ethers.utils.formatEther(allowance);
}



// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
