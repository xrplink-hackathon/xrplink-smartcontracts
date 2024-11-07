// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./XrpERC20.sol";
import "./PoolERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract XrpERC20Factory is Ownable {
    address immutable tokenImplementation;
    address immutable poolImplementation;
    address payable public feeRecipient;
    uint256 public fee;

    constructor() {
        Ownable(msg.sender);
        tokenImplementation = address(new XrpERC20());
        poolImplementation = address(new PoolERC20());
        feeRecipient = payable(msg.sender); 
        fee = 0;
    }

    event CreateToken(address addr, address deployer, string id);
    event CreatePoolToken(
        address addr,
        address deployer,
        address addrToken,
        address exchanger,
        string id
    );

    receive() external payable {}

    fallback() external payable {}

    //===============================OWNER FUNCTION===============================
    // set fee
    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    // set fee recipient
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(
            _feeRecipient != address(0),
            "Fee recipient address cannot be zero address"
        );
        feeRecipient = payable(_feeRecipient);
    }

    //===============================INTERNAL FUNCTIONS===============================
    //clone contract token
    function _createToken(
        string memory name,
        string memory symbol,
        bytes32 salt,
        string calldata id
    ) internal returns (address) {
        bytes32 cloneSalt = keccak256(
            abi.encodePacked(salt, msg.sender, blockhash(block.number))
        );
        address clone = Clones.cloneDeterministic(
            tokenImplementation,
            cloneSalt
        );
        XrpERC20(clone).initialize(msg.sender, feeRecipient, name, symbol);

        emit CreateToken(clone, msg.sender, id);

        return clone;
    }

    // clone poolToken
    function _createPoolToken(
        address _tokenAddress,
        address _exchanger,
        bytes32 salt,
        string calldata id
    ) internal returns (address) {
        bytes32 cloneSalt = keccak256(
            abi.encodePacked(
                salt,
                msg.sender,
                _exchanger,
                blockhash(block.number)
            )
        );
        address payable clone = payable(
            Clones.cloneDeterministic(poolImplementation, cloneSalt)
        );
        PoolERC20(clone).initialize(_tokenAddress, _exchanger);

        emit CreatePoolToken(clone, msg.sender, _tokenAddress, _exchanger, id);

        return clone;
    }

    //===============================PUBLIC FUNCTIONS===============================
    function createToken(
        string memory name,
        string memory symbol,
        bytes32 salt,
        string calldata id
    ) public payable returns (address) {
        require(fee == msg.value, "Invalid gas fee create token");
        payable(feeRecipient).transfer(fee);

        return _createToken(name, symbol, salt, id);
    }

    function createPoolToken(
        address tokenAddress,
        address exchanger,
        bytes32 salt,
        string calldata id
    ) public payable returns (address) {
        require(fee == msg.value, "Invalid gas fee create pool token");
        require(tokenAddress != address(0), "Token address not be address 0");
        payable(feeRecipient).transfer(fee);

        return _createPoolToken(tokenAddress, exchanger, salt, id);
    }
}
