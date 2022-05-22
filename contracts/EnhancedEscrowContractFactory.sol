pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./EnhancedEscrowContract.sol";

contract EnhancedEscrowContractFactory is Ownable {

//    address public beneficiary;
//    address public payer;
    uint24 public feePercentage = 5000;//0.5%

    //Beneficiary => payer => Escrow contract
    mapping (address => mapping (address => address)) public escrowContractList;




    function deploy(
        address beneficiary,
        address payer
    ) public  {

        require(
            escrowContractList[beneficiary][payer] == address(0),
            "EscrowContractFactory::deploy: already deployed"
        );

        escrowContractList[beneficiary][payer] = address(
            new EnhancedEscrowContract(payer, beneficiary, address(this), feePercentage)
        );

    }



    function updateFee(uint24 _fee) public onlyOwner {
        require(_fee < 1000000, "the value fee percentage is out of range");
        feePercentage = _fee;
    }


    function refundByMediator(address beneficiary, address payer) external onlyOwner {
        EnhancedEscrowContract(escrowContractList[beneficiary][payer]).refundByMediator();
    }

    function releaseByMediator(address beneficiary, address payer) external onlyOwner {
        EnhancedEscrowContract(escrowContractList[beneficiary][payer]).releaseByMediator();
    }

    //TODO function to pull(rescue) token from Escrow Account should be developed

    function pullExtraTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }
}
