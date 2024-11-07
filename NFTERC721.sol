// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./libraries/Lib.sol";

contract NFTERC721 is ERC721Upgradeable, OwnableUpgradeable {
    event MintNFT(
        address to,
        uint256 tokenID,
        string name,
        string description,
        string image,
        string idAtributes
    );

    string public baseURI;
    uint256 public nextTokenId;
    uint256 public totalSupply;
    address payable public feeRoyaltyRecipient;
    uint256 public feeRoyalty;

    function initialize(
        address ownerAddress,
        address payable _feeRoyaltyRecipient,
        string calldata _name,
        string calldata _symbol,
        string calldata _uri,
        uint256 _totalSupply
    ) public initializer {
        __ERC721_init_unchained(_name, _symbol);
        __Ownable_init_unchained();

        transferOwnership(ownerAddress);

        nextTokenId = 1;
        totalSupply = _totalSupply;
        baseURI = _uri;
        feeRoyaltyRecipient = payable(_feeRoyaltyRecipient);
    }

    //-----------------------------OWNER FUNCTION-----------------------------------
    function setTotalSupply(uint256 _totalSupply) external onlyOwner {
        require(
            _totalSupply > totalSupply,
            "New total supply must be greater than current total supply"
        );
        totalSupply = _totalSupply;
    }

    function setFeeRoyalty(uint256 _feeRoyalty) external onlyOwner {
        feeRoyalty = _feeRoyalty;
    }

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
    }

    //------------------------------PUBLIC FUNCTION----------------------------------

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        return String.strConcat(super.tokenURI(tokenId), ".json");
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    //------------------------------EXCUTE FUNCTION----------------------------------

    /**
     * Allow anyone to mint an NFT by paying the required fee.
     * @param name name of nft
     * @param description description of nft
     * @param image url of nft's image, must be ipfs
     * @param idAtributes The Id attributes will be stored in the openworld system to synchronize data
     */
    function mint(
        string memory name,
        string memory description,
        string memory image,
        string memory idAtributes
    ) external payable {
        require(msg.value == feeRoyalty, "Not enough mint fee");
        require(nextTokenId <= totalSupply, "Exceed cap");

        payable(feeRoyaltyRecipient).transfer(feeRoyalty);
        uint256 id = nextTokenId;
        _safeMint(msg.sender, id);
        nextTokenId++;

        emit MintNFT(msg.sender, id, name, description, image, idAtributes);
    }

    /**
     * Require You must be owner of nft
     * @param tokenId token Id you want to burn
     */
    function burn(uint256 tokenId) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Caller is not owner nor approved");
        _burn(tokenId);
    }
}
