pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


contract EscrowContract is
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
        uint8 status;//1: deposited, 2: released, 3: dispute
    }

    uint256 counter;//used for bill id

    mapping (uint256 => PaymentInfo) public invoiceList;
    //TODO read array value through etherjs
    PaymentInfo[] public activeDeals;

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

    //TODO expiry timestamp, invoiceID
    function sendInvoice (address currency, uint256 amount) external {
        require(msg.sender == beneficiary, "Only beneficiary can create invoice");
        require(invoiceList[counter].currency == address(0), "contract is broken");
        invoiceList[counter] = PaymentInfo(currency, amount, (block.timestamp).add(SECONDS_IN_A_WEEK), 0);
        counter += 1;
    }


    //TODO approval is required before execute this function
    function depositFund() external {
        require(msg.sender == payer, "Only payer can deposit the fund");
        //TODO fetch latest issued paymentInfo. this can be tailored by specifying bill id.
        PaymentInfo storage invoice = invoiceList[counter-1];
        IERC20(invoice.currency).transferFrom(msg.sender, address(this), invoice.amount);
        invoice.status = 1;
        //TODO should be able to process multiple deals at the same time in the future
        require(activeDeals.length == 0, "Only one active deal can proceed at the moment");
        activeDeals.push(invoice);
    }

    //TODO function
    function depositBillOfLading() external{
        require(msg.sender == beneficiary, "Only beneficiary can deposit BL");
    }

    //Ok to release the fund.
    function acceptDeal() external {
        require(msg.sender == payer, "Only payer can accept the deal");
        require(activeDeals.length > 0, "There must be active deal to be accepted");
        //TODO should be specifiable by this function in the future. Currently take the first one.
        PaymentInfo storage deal = activeDeals[0];
        uint256 escrowFee = deal.amount.mul(transactionFee).div(1000000);
        IERC20(deal.currency).transfer(beneficiary, deal.amount.sub(escrowFee));
        IERC20(deal.currency).transfer(mediator, escrowFee);
        deal.status = 2;
        activeDeals.pop();
        require(activeDeals.length == 0, "Only one active deal is accepted at the moment");
    }

    //beneficiary agrees with refund to payer
    function refund() external {
        require(msg.sender == beneficiary, "Only beneficiary can proceed the refund");
        require(activeDeals.length > 0, "There must be active deal to be accepted");
        //TODO should be specifiable by this function in the future. Currently take the first one.
        PaymentInfo storage deal = activeDeals[0];
        uint256 escrowFee = deal.amount.mul(transactionFee).div(1000000);
        IERC20(deal.currency).transfer(payer, deal.amount.sub(escrowFee));
        IERC20(deal.currency).transfer(mediator, escrowFee);
        deal.status = 2;
        activeDeals.pop();
        require(activeDeals.length == 0, "Only one active deal is accepted at the moment");
    }

    //TODO
    //receive BL NFT and release the fund
    function confirmDelivery2() external {
    }

    function askArbitration() external {
        require((msg.sender == payer) || (msg.sender == beneficiary), "Only payer or beneficiary can ask the arbitration to mediator");
        activeDeals[0].status = 3;
    }

    function refundByMediator() external {
        require(msg.sender == mediator, "This process is mediator only");
        require(activeDeals.length > 0, "There must be active deal to be accepted");
        require(activeDeals[0].status == 3, "Neither payer nor beneficiary asked to mediate a dispute");
        PaymentInfo storage deal = activeDeals[0];
        //Escrow fee will be 10 times more, as mediator is bothered.
        uint256 escrowFee = deal.amount.mul(transactionFee).mul(10).div(1000000);
        IERC20(deal.currency).transfer(payer, deal.amount.sub(escrowFee));
        IERC20(deal.currency).transfer(mediator, escrowFee);
        deal.status = 2;
        activeDeals.pop();
        require(activeDeals.length == 0, "Only one active deal is accepted at the moment");
    }

    //Complete the deal and send money to beneficiary
    function releaseByMediator() external {
        require(msg.sender == mediator, "This process is mediator only");
        require(activeDeals.length > 0, "There must be active deal to be accepted");
        require(activeDeals[0].status == 3, "Neither payer nor beneficiary asked to mediate a dispute");
        PaymentInfo storage deal = activeDeals[0];
        //Escrow fee will be 10 times more, as mediator is bothered.
        uint256 escrowFee = deal.amount.mul(transactionFee).mul(10).div(1000000);
        IERC20(deal.currency).transfer(beneficiary, deal.amount.sub(escrowFee));
        IERC20(deal.currency).transfer(mediator, escrowFee);
        deal.status = 2;
        activeDeals.pop();
        require(activeDeals.length == 0, "Only one active deal is accepted at the moment");

    }


    //recover token wrongly deposited
    function pullTokens(address token) external {
        require(msg.sender == mediator, "only mediator can recover the fund");
        uint256 amount = IERC20(token).balanceOf(address(this));
        require(amount > 0, "There is no fund to be pull");
        if(activeDeals.length == 0){
            IERC20(token).transfer(mediator, amount);
        } else if(token != activeDeals[0].currency){
            IERC20(token).transfer(mediator, amount);
        } else {
            require(amount > activeDeals[0].amount, "Fund is reserved for a deal and should not be pull");
            IERC20(token).transfer(mediator, amount.sub(activeDeals[0].amount));
        }
    }


    /* ========== RESTRICTED FUNCTIONS ========== */



    /* ========== MODIFIERS ========== */


}

