// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./XrpERC721.sol";
import "./PoolERC721.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract XrpERC721Factory is Ownable {
    address immutable nftImplementation;
    address immutable poolNFTImplementation;
    address payable public feeRecipient;
    uint256 public fee;

    constructor(address _feeRecipient) {
        Ownable(msg.sender);
        nftImplementation = address(new XrpERC721());
        poolNFTImplementation = address(new PoolERC721());
        feeRecipient = payable(_feeRecipient);
    }

    event CreateNFT(address addr, address deployer, string id);
    event CreatePoolNFT(
        address addr,
        address deployer,
        address tokenAddress,
        address exchanger,
        string id
    );

    //===============================EXTERNAL FUNCTION===============================
    receive() external payable {}

    fallback() external payable {}

    //===============================OWNER FUNCTION===============================

    function setFee(uint256 _fee) public onlyOwner {
        fee = _fee;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(
            _feeRecipient != address(0),
            "Fee recipient address cannot be zero address"
        );
        feeRecipient = payable(_feeRecipient);
    }

    //===============================INTERNAL FUNCTION===============================

    function _createNFT(
        string memory name,
        string memory symbol,
        string memory uri,
        uint256 totalSupply,
        bytes32 salt,
        string calldata id
    ) internal returns (address clone) {
        bytes32 cloneSalt = keccak256(
            abi.encodePacked(salt, msg.sender, blockhash(block.number))
        );
        clone = Clones.cloneDeterministic(nftImplementation, cloneSalt);
        XrpERC721(clone).initialize(
            msg.sender,
            feeRecipient,
            name,
            symbol,
            uri,
            totalSupply
        );

        emit CreateNFT(clone, msg.sender, id);
    }

    function _createPoolNFT(
        address _tokenAddress,
        address _exchanger,
        bytes32 salt,
        string calldata id
    ) internal returns (address) {
        bytes32 cloneSalt = keccak256(
            abi.encodePacked(salt, msg.sender, blockhash(block.number))
        );
        address payable clone = payable(
            Clones.cloneDeterministic(poolNFTImplementation, cloneSalt)
        );
        PoolERC721(clone).initialize(_tokenAddress, _exchanger);

        emit CreatePoolNFT(clone, msg.sender, _tokenAddress, _exchanger, id);
        return clone;
    }

    //===============================PUBLIC FUNCTION===============================

    function createNFT(
        string memory name,
        string memory symbol,
        uint256 _totalSupply,
        string memory uri,
        bytes32 salt,
        string calldata id
    ) public payable returns (address) {
        require(fee == msg.value, "Invalid fee create nft");

        payable(feeRecipient).transfer(fee);

        return _createNFT(name, symbol, uri, _totalSupply, salt, id);
    }

    function createPoolNFT(
        address _tokenAddress,
        address _exchanger,
        bytes32 salt,
        string calldata id
    ) public payable returns (address) {
        require(fee == msg.value, "Invalid fee create pool nft");
        require(_tokenAddress != address(0), "Invalid token address");

        payable(feeRecipient).transfer(fee);

        return _createPoolNFT(_tokenAddress, _exchanger, salt, id);
    }
}
