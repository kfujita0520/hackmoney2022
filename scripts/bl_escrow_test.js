// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
//const {moveTime} = require("../utils/move-time");
//const {moveBlocks} = require("../utils/move-blocks");

let escrowFactory, escrowA, usdToken, blToken, tokenId, escrowContractAddr, deployer, beneficiary, payer, other;

const SECONDS_IN_A_HOUR = 3600
const SECONDS_IN_A_DAY = 86400
const SECONDS_IN_A_WEEK = 604800
const SECONDS_IN_A_YEAR = 31449600

const BL_URI = "ipfs://bafkreigpmlugdvkgvod4epscdtdfiqthlecwwrizcyzwanyrynueyiu5we";

async function main() {

    await initialSetup();

    await normalSenario();

    //await unauthorizedAccess();

    //await refundByMediator();


    console.log('Complete');

}

async function initialSetup(){
    [deployer, beneficiary, payer, other] = await hre.ethers.getSigners();
    console.log('Deployer: ', deployer.address);
    console.log('Beneficiary: ', beneficiary.address);
    console.log('Payer: ', payer.address);
    const usdTokenContract = await hre.ethers.getContractFactory("USDToken");
    usdToken = await usdTokenContract.deploy();
    await usdToken.deployed();
    console.log("usdToken deployed to:", usdToken.address);

    const escrowFactoryContract = await hre.ethers.getContractFactory("EnhancedEscrowContractFactory");
    escrowFactory = await escrowFactoryContract.deploy();
    await escrowFactory.deployed();
    console.log("escrowFactory deployed to:", escrowFactory.address);

    //TODO deploy more than one staking contract with StakeTokenB
    await escrowFactory.deploy(beneficiary.address, payer.address);
    escrowContractAddr = await escrowFactory.escrowContractList(beneficiary.address, payer.address);
    console.log("Escrow Contract: ", escrowContractAddr);
    escrowA = await hre.ethers.getContractAt("EnhancedEscrowContract", escrowContractAddr);

    //move usd token to payer for his payment
    await usdToken.transfer(payer.address, hre.ethers.utils.parseEther("100000"));
    await usdToken.connect(payer).approve(escrowA.address, hre.ethers.constants.MaxUint256);
    //await usdToken.transfer(other.address, hre.ethers.utils.parseEther("100000"));

    //issue BL token and get beneficiary approve escrow contract to move it
    const blTokenContract = await hre.ethers.getContractFactory("BillOfLading");
    blToken = await blTokenContract.deploy();
    await blToken.deployed();
    console.log("billOfLading deployed to:", blToken.address);
    await blToken.safeMint(beneficiary.address, BL_URI);
    tokenId = (await blToken.getCounter()-1);
    console.log("token id", tokenId);
    await blToken.connect(beneficiary).approve(escrowContractAddr, tokenId);
    console.log("Owner of token", await blToken.ownerOf(tokenId));
}

async function normalSenario(){
    let amount1000 = hre.ethers.utils.parseEther("1000");
    await escrowA.connect(beneficiary).sendInvoice(usdToken.address, amount1000);
    console.log("balance of escrow contract: ", await printBalance(escrowA.address));
    await escrowA.connect(payer).depositFund();
    console.log("balance of escrow contract: ", await printBalance(escrowA.address));
    console.log("balance of beneficiary: ", await printBalance(beneficiary.address));
    console.log("balance of payer: ", await printBalance(payer.address));
    console.log("BL Info of the deal", (await escrowA.activeDeals(0)).blInfo);
    await escrowA.connect(payer).verifyAndRequestBillOfLading(blToken.address, tokenId);
    console.log("BL Info of the deal", (await escrowA.activeDeals(0)).blInfo);
    console.log("Owner of BL: ", await blToken.ownerOf(tokenId));
    await escrowA.connect(beneficiary).depositBillOfLading();
    console.log("Owner of BL: ", await blToken.ownerOf(tokenId));

    await escrowA.connect(payer).acceptDeal();
    console.log("balance of escrow contract: ", await printBalance(escrowA.address));
    console.log("balance of factory contract: ", await printBalance(escrowFactory.address));
    console.log("balance of beneficiary: ", await printBalance(beneficiary.address));
    console.log("Owner of BL: ", await blToken.ownerOf(tokenId));
}

async function unauthorizedAccess(){
    let isAskMediator = false;

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

    await escrowA.connect(payer).acceptDeal().then(result => {
        console.log("acceptance is succeed by payer");
    }).catch(err => {
        console.log("The deal is not ready for Acceptance. Need BL");
    });


    await escrowA.connect(beneficiary).depositBillOfLading().then(result => {
        console.log("depositBL is succeed by beneficiary");
    }).catch(err => {
        console.log("BL must be verified by payer");
    });

    await escrowA.connect(payer).verifyAndRequestBillOfLading(blToken.address, tokenId);

    console.log("balance of escrow contract: ", await printBalance(escrowA.address));
    console.log("balance of factory contract: ", await printBalance(escrowFactory.address));
    console.log("balance of beneficiary: ", await printBalance(beneficiary.address));

    if(isAskMediator){
        await escrowA.connect(payer).askArbitration();
        await escrowFactory.connect(deployer).releaseByMediator(beneficiary.address, payer.address).then(result => {
            console.log("successful release by mediator");
        }).catch(err => {
            console.log("BL is not deposited yet");
        });;
    }

    await escrowA.connect(beneficiary).depositBillOfLading();
    console.log("Owner of BL: ", await blToken.ownerOf(tokenId));

    await escrowA.connect(beneficiary).depositBillOfLading().then(result => {
        console.log("deposit BL success");
    }).catch(err => {
        console.log("ERC721: transfer from incorrect owner");
    });

    await escrowA.connect(payer).acceptDeal().then(result => {
        console.log("accept success");
    }).catch(err => {
        console.log("There must be active deal to be accepted");
    });
}

async function refundByMediator(){
    let isBLDeposit = true;

    let amount1000 = hre.ethers.utils.parseEther("1000");
    await escrowA.connect(beneficiary).sendInvoice(usdToken.address, amount1000);
    console.log("balance of escrow contract: ", await printBalance(escrowA.address));
    await escrowA.connect(payer).depositFund();
    console.log("balance of escrow contract: ", await printBalance(escrowA.address));
    console.log("balance of beneficiary: ", await printBalance(beneficiary.address));
    console.log("balance of payer: ", await printBalance(payer.address));

    await escrowA.connect(payer).verifyAndRequestBillOfLading(blToken.address, tokenId);
    console.log("BL Info of the deal", (await escrowA.activeDeals(0)).blInfo);
    console.log("Owner of BL: ", await blToken.ownerOf(tokenId));
    console.log("Status of Deal: ", (await escrowA.activeDeals(0)).status);
    if(isBLDeposit){
        await escrowA.connect(beneficiary).depositBillOfLading();
        console.log("Owner of BL: ", await blToken.ownerOf(tokenId));
    }


    await escrowA.connect(payer).askArbitration();
    await escrowA.connect(beneficiary).askArbitration();
    console.log("Status of Deal: ", (await escrowA.activeDeals(0)).status);

    await escrowFactory.connect(deployer).refundByMediator(beneficiary.address, payer.address);
    console.log("balance of escrow contract: ", await printBalance(escrowA.address));
    console.log("balance of factory contract: ", await printBalance(escrowFactory.address));
    console.log("balance of beneficiary: ", await printBalance(beneficiary.address));
    console.log("balance of payer: ", await printBalance(payer.address));
    console.log("Owner of BL: ", await blToken.ownerOf(tokenId));

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
