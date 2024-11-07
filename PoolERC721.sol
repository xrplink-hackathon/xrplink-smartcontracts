// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/interfaces/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "hardhat/console.sol";

contract PoolERC721 is
    ReentrancyGuardUpgradeable,
    IERC721ReceiverUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    IERC721Upgradeable public tokenERC721;

    uint256 public totalNFTsClaimed;
    address payable public feeRecipient;
    uint256 public fee;
    //user => tokenid deposit
    mapping(address => mapping(uint256 => bool)) public userDeposits;
    //list exchanger
    mapping(address => bool) public whitelistedExchanger;

    uint256[] public listTokenIds;


    //address => nonce => true/false
    mapping(address => mapping(uint256 => bool)) public userUsedNonces;
    mapping(address => bool) public isClaimed;
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "ClaimNFT(address from, address to, uint256 tokenId, uint256 nonce)"
        );
    event TransferNftForUser(
        address userAddress,
        uint256 tokenId,
        uint256 nonce,
        string id
    );
    event ClaimNFT(
        address userAddress,
        uint256 tokenId,
        uint256 nonce,
        string id
    );
    event DepositNfts(address userAddress, uint256 tokenId, string id);

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}

    function initialize(
        address _tokenAddress,
        address _exchanger
    ) public initializer {
        __ReentrancyGuard_init_unchained();
        __Ownable_init_unchained();
        __Pausable_init_unchained();

        //feeRecipient = payable(_feeRecipient);
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("PoolERC721")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );

        tokenERC721 = IERC721Upgradeable(_tokenAddress);
        feeRecipient = payable(_exchanger);
        fee = 0;
        whitelistedExchanger[_exchanger] = true;
    }

    //===============================ADMIN FUNCTIONS===============================
    modifier onlyExchanger() {
        require(
            whitelistedExchanger[msg.sender],
            "Not whitelisted as Exchanger"
        );
        _;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @param _feeRecipient address fee recipient Owner want to change, not be address 0
     */
    function setFeeRecipient(address _feeRecipient) external onlyExchanger {
        require(
            _feeRecipient != address(0),
            "Recipient address cannot be address 0"
        );
        feeRecipient = payable(_feeRecipient);
    }

    /**
     *
     * @param _fee Set new fee to claim nft
     */
    function setFee(uint256 _fee) external onlyExchanger {
        fee = _fee;
    }

    function setExchanger(
        address _exchanger,
        bool _whitelisted
    ) external onlyExchanger {
        require(
            _exchanger != address(0),
            "Exchanger address cannot be address 0"
        );
        require(
            whitelistedExchanger[_exchanger] != _whitelisted,
            "Invalid value for exchanger"
        );
        whitelistedExchanger[_exchanger] = _whitelisted;
    }

    function rescueStuckNFT(
        address to,
        uint256 tokenId
    ) external onlyExchanger {
        tokenERC721.safeTransferFrom(address(this), to, tokenId);
    }

    //===============================EXTERNAL FUNCTIONS===============================

    function depositNFTs(
        uint256[] calldata tokenIds,
        string calldata id
    ) external nonReentrant whenNotPaused {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenERC721.safeTransferFrom(
                msg.sender,
                address(this),
                tokenIds[i]
            );
            userDeposits[msg.sender][tokenIds[i]] = true;
            //console.log(tokenIds[i]);
            listTokenIds.push(tokenIds[i]);
            emit DepositNfts(msg.sender, tokenIds[i], id);
        }
    }

    function transferNftForUser(
        uint256 tokenId,
        uint256 nonce,
        bytes memory _serverSig,
        string calldata id
    ) external nonReentrant whenNotPaused {
        address userAddress = msg.sender;

        require(
            tokenERC721.ownerOf(tokenId) == address(this),
            "Token not owned by contract"
        );
        require(!userUsedNonces[userAddress][nonce], "Nonce already used");
        require(
            verifySignature(
                address(this),
                userAddress,
                tokenId,
                nonce,
                _serverSig
            ),
            "Not valid signature from server"
        );

        tokenERC721.safeTransferFrom(address(this), userAddress, tokenId);
        userUsedNonces[userAddress][nonce] = true;
        userDeposits[msg.sender][tokenId] = false;

        emit TransferNftForUser(userAddress, tokenId, nonce, id);
    }

    function _removeTokenIdFromList(uint256 tokenId) internal {
        uint256 length = listTokenIds.length;

        for (uint256 i = 0; i < length; i++) {
            if (listTokenIds[i] == tokenId) {
                // Move the last element into the place of the one to be removed
                listTokenIds[i] = listTokenIds[length - 1];

                // Remove the last element by reducing the array length
                listTokenIds.pop();
                break;
            }
        }
    }

    function claimNFT(
        uint256 tokenId,
        uint256 nonce,
        bytes memory _serverSig,
        string calldata id
    ) external payable nonReentrant whenNotPaused {
        address userAddress = msg.sender;

        require(
            tokenERC721.ownerOf(tokenId) == address(this),
            "Token not owned by contract"
        );
        require(!userUsedNonces[userAddress][nonce], "Nonce already used");
        require(msg.value == fee, "Not enough fee to claim NFT");
         require(!isClaimed[userAddress], "claimed already!");
        require(
            verifySignature(
                address(this),
                userAddress,
                tokenId,
                nonce,
                _serverSig
            ),
            "Not valid signature from server"
        );

        userUsedNonces[userAddress][nonce] = true;
        isClaimed[userAddress] = true;
        //transfer
        payable(feeRecipient).transfer(fee);
        tokenERC721.safeTransferFrom(address(this), msg.sender, tokenId);

        _removeTokenIdFromList(tokenId);
        emit ClaimNFT(userAddress, tokenId, nonce, id);
    }

    function getPoolInfo()
        external
        view
        returns (uint256 numNFTsInPool, uint256 numNFTsClaimed)
    {
        numNFTsInPool = tokenERC721.balanceOf(address(this));
        numNFTsClaimed = totalNFTsClaimed;
    }
    function getListId()
        external
        view
        returns (uint256[] memory ids)
    {
        ids = listTokenIds;
    }
    //===============================SIGNATURE===============================

    function verifySignature(
        address from,
        address to,
        uint256 tokenId,
        uint256 nonce,
        bytes memory serverSig
    ) public view returns (bool) {
        bytes32 signedMessage = prefixed(
            keccak256(
                abi.encodePacked(
                    DOMAIN_SEPARATOR,
                    PERMIT_TYPEHASH,
                    from,
                    to,
                    tokenId,
                    nonce
                )
            )
        );

        return whitelistedExchanger[recoverSigner(signedMessage, serverSig)];
    }

    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
            );
    }

    function recoverSigner(
        bytes32 message,
        bytes memory sig
    ) public pure returns (address) {
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = splitSignature(sig);
        return ecrecover(message, v, r, s);
    }

    function splitSignature(
        bytes memory sig
    ) public pure returns (uint8, bytes32, bytes32) {
        require(sig.length == 65);

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        return (v, r, s);
    }

    //================================PURE FUNCTIONS=============================

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
