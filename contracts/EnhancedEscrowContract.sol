pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";


contract EnhancedEscrowContract is
ReentrancyGuard
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    address public payer;
    address public beneficiary;
    address public mediator;
    uint24 public transactionFee;


    struct PaymentInfo {
        address currency;
        uint256 amount;
        uint256 dueDate;
    }

    struct BLInfo {
        address tokenAddress;
        uint256 tokenId;
    }


    struct DealInfo {
        PaymentInfo paymentInfo;
        BLInfo blInfo;
        uint8 status;//1: deposited fund, 2: deposited BL, 3: released, 4: dispute
    }

    uint256 counter;//used for bill id

    mapping (uint256 => PaymentInfo) public invoiceList;
    //TODO read array value through etherjs
    DealInfo[] public activeDeals;

    uint256 SECONDS_IN_A_WEEK = 604800;


    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _payer,
        address _beneficiary,
        address _mediator,
        uint24 _transactionFee
    ) public {
        payer = _payer;
        beneficiary = _beneficiary;
        mediator = _mediator;
        counter = 0;
        transactionFee = _transactionFee;
    }

    /* ========== VIEWS ========== */





    /* ========== MUTATIVE FUNCTIONS ========== */

    //TODO support expiry timestamp, invoiceID argument
    function sendInvoice (address currency, uint256 amount) external {
        require(msg.sender == beneficiary, "Only beneficiary can create invoice");
        require(invoiceList[counter].currency == address(0), "contract is broken");
        invoiceList[counter] = PaymentInfo(currency, amount, (block.timestamp).add(SECONDS_IN_A_WEEK));
        counter += 1;
    }


    //TODO approval is required before execute this function
    function depositFund() external {
        require(msg.sender == payer, "Only payer can deposit the fund");
        //TODO fetch latest issued paymentInfo. this can be tailored by specifying bill id.
        PaymentInfo storage invoice = invoiceList[counter-1];
        IERC20(invoice.currency).transferFrom(msg.sender, address(this), invoice.amount);
        //TODO should be able to process multiple deals at the same time in the future
        require(activeDeals.length == 0, "Only one active deal can proceed at the moment");
        BLInfo memory bl;
        activeDeals.push(DealInfo(invoice, bl, 1));
    }

    //TODO once it is verified, should not be changable? or after deposited?
    function verifyAndRequestBillOfLading(address BLToken, uint256 tokenId) external{
        require(msg.sender == payer, "Only payer can request BL");
        require(activeDeals.length > 0, "There must be active deal to be accepted");
        activeDeals[0].blInfo = BLInfo(BLToken, tokenId);

    }

    //TODO function
    function depositBillOfLading() external{
        require(msg.sender == beneficiary, "Only beneficiary can deposit BL");
        require(activeDeals.length > 0, "There must be active deal to be accepted");
        DealInfo storage deal = activeDeals[0];
        require(deal.blInfo.tokenAddress != address(0), "BL must be verified by payer");
        IERC721Metadata(activeDeals[0].blInfo.tokenAddress).transferFrom(beneficiary, address(this), activeDeals[0].blInfo.tokenId);
        deal.status = 2;
    }

    //Ok to release the fund.
    function acceptDeal() external {
        require(msg.sender == payer, "Only payer can accept the deal");
        //TODO use isBLDeposited method for validation
        require(activeDeals.length > 0 && activeDeals[0].status == 2, "There must be active deal to be ready for the acceptance");
        //TODO deal element should be specifiable by this function in the future. Currently take the first one.
        DealInfo storage deal = activeDeals[0];
        uint256 escrowFee = deal.paymentInfo.amount.mul(transactionFee).div(1000000);
        IERC20(deal.paymentInfo.currency).transfer(beneficiary, deal.paymentInfo.amount.sub(escrowFee));
        IERC20(deal.paymentInfo.currency).transfer(mediator, escrowFee);
        IERC721Metadata(deal.blInfo.tokenAddress).transferFrom(address(this), payer, deal.blInfo.tokenId);
        deal.status = 3;
        activeDeals.pop();
        require(activeDeals.length == 0, "Only one active deal is accepted at the moment");
    }

    //beneficiary agrees with refund to payer
    function refund() external {
        require(msg.sender == beneficiary, "Only beneficiary can proceed the refund");
        require(activeDeals.length > 0, "There must be active deal to be accepted");
        //TODO should be specifiable by this function in the future. Currently take the first one.
        DealInfo storage deal = activeDeals[0];
        uint256 escrowFee = deal.paymentInfo.amount.mul(transactionFee).div(1000000);
        IERC20(deal.paymentInfo.currency).transfer(payer, deal.paymentInfo.amount.sub(escrowFee));
        IERC20(deal.paymentInfo.currency).transfer(mediator, escrowFee);
        if(isBLDeposited()){
            IERC721Metadata(deal.blInfo.tokenAddress).transferFrom(address(this), beneficiary, deal.blInfo.tokenId);
        }
        deal.status = 3;
        activeDeals.pop();
        require(activeDeals.length == 0, "Only one active deal is accepted at the moment");
    }

    //TODO
    //receive BL NFT and release the fund
    function confirmDelivery2() external {
    }

    function askArbitration() external {
        require((msg.sender == payer) || (msg.sender == beneficiary), "Only payer or beneficiary can ask the arbitration to mediator");
        activeDeals[0].status = 4;
    }

    function refundByMediator() external {
        require(msg.sender == mediator, "This process is mediator only");
        require(activeDeals.length > 0, "There must be active deal to be accepted");
        require(activeDeals[0].status == 4, "Neither payer nor beneficiary asked to mediate a dispute");
        DealInfo storage deal = activeDeals[0];
        //Escrow fee will be 10 times more, as mediator is bothered.
        uint256 escrowFee = deal.paymentInfo.amount.mul(transactionFee).mul(10).div(1000000);
        IERC20(deal.paymentInfo.currency).transfer(payer, deal.paymentInfo.amount.sub(escrowFee));
        IERC20(deal.paymentInfo.currency).transfer(mediator, escrowFee);
        if(isBLDeposited()){
            IERC721Metadata(deal.blInfo.tokenAddress).transferFrom(address(this), beneficiary, deal.blInfo.tokenId);
        }
        deal.status = 3;
        activeDeals.pop();
        require(activeDeals.length == 0, "Only one active deal is accepted at the moment");
    }

    //Complete the deal and send money to beneficiary
    function releaseByMediator() external {
        require(msg.sender == mediator, "This process is mediator only");
        require(activeDeals.length > 0, "There must be active deal to be accepted");
        require(activeDeals[0].status == 4, "Neither payer nor beneficiary asked to mediate a dispute");
        require(isBLDeposited(), "BL is not deposited yet");
        DealInfo storage deal = activeDeals[0];
        //Escrow fee will be 10 times more, as mediator is bothered.
        uint256 escrowFee = deal.paymentInfo.amount.mul(transactionFee).mul(10).div(1000000);
        IERC20(deal.paymentInfo.currency).transfer(beneficiary, deal.paymentInfo.amount.sub(escrowFee));
        IERC20(deal.paymentInfo.currency).transfer(mediator, escrowFee);
        deal.status = 3;
        activeDeals.pop();
        require(activeDeals.length == 0, "Only one active deal is accepted at the moment");

    }

    function isBLDeposited() public returns(bool){

        if(activeDeals.length <= 0){
            return false;
        } else if (activeDeals[0].blInfo.tokenAddress == address(0)){
            return false;
        } else if (IERC721Metadata(activeDeals[0].blInfo.tokenAddress).ownerOf(activeDeals[0].blInfo.tokenId) != address(this)){
            return false;
        } else {
            return true;
        }

    }


    //recover token wrongly deposited
    function pullTokens(address token) external {
        require(msg.sender == mediator, "only mediator can recover the fund");
        uint256 amount = IERC20(token).balanceOf(address(this));
        require(amount > 0, "There is no fund to be pull");
        if(activeDeals.length == 0){
            IERC20(token).transfer(mediator, amount);
        } else if(token != activeDeals[0].paymentInfo.currency){
            IERC20(token).transfer(mediator, amount);
        } else {
            require(amount > activeDeals[0].paymentInfo.amount, "Fund is reserved for a deal and should not be pull");
            IERC20(token).transfer(mediator, amount.sub(activeDeals[0].paymentInfo.amount));
        }
    }


    /* ========== RESTRICTED FUNCTIONS ========== */



    /* ========== MODIFIERS ========== */


}

