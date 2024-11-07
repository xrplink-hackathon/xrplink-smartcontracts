// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "hardhat/console.sol";

contract PoolERC20 is
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    IERC20Upgradeable public tokenERC20;
    address payable public feeRecipient;
    uint256 public fee;
    uint256 public totalTokensClaimed;

    // address => nonce => true/false
    mapping(address => mapping(uint256 => bool)) public usersNonce;
    mapping(address => bool) public isClaimed;
    // list exchanger
    mapping(address => bool) public whitelistedExchanger;
    //user => amountUserDeposit
    mapping(address => uint256) public userDeposits;

    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "ClaimToken(address from, address to, uint256 amount, uint256 nonce)"
        );

    event TransferTokensForUser(
        address userAddress,
        uint256 amount,
        uint256 nonce,
        string id
    );
    event ClaimToken(
        address userAddress,
        uint256 amount,
        uint256 nonce,
        string id
    );
    event Deposit(address userAddress, uint256 amount, string id);

    modifier onlyExchanger() {
        require(
            whitelistedExchanger[msg.sender],
            "Not whitelisted as Exchanger"
        );
        _;
    }

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

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("PoolERC20")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );

        tokenERC20 = IERC20Upgradeable(_tokenAddress);
        feeRecipient = payable(_exchanger);
        fee = 0;
        whitelistedExchanger[_exchanger] = true;
    }

    //==================================ADMIN FUNCTION==================================
    function pause() external onlyExchanger {
        _pause();
    }

    function unpause() external onlyExchanger {
        _unpause();
    }

    /**
     * @param _recipient address fee recipient Owner want to change, not be address 0
     */
    function setFeeRecipient(address _recipient) external onlyExchanger {
        require(
            _recipient != address(0),
            "Recipient address cannot be address 0"
        );
        feeRecipient = payable(_recipient);
    }

    /**
     *
     * @param _fee Set new fee to claim token
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

    function rescueStuckToken(
        address to,
        uint256 amount
    ) external onlyExchanger {
        bool sent = tokenERC20.transfer(to, amount);
        require(sent, "Failed to transfer token");
    }

    //==================================EXTERNAL FUNCTION==================================
    function depositToken(
        uint256 amount,
        string calldata id
    ) external nonReentrant whenNotPaused {
        bool sent = tokenERC20.transferFrom(msg.sender, address(this), amount);
        require(sent, "Failed to transfer token");
        userDeposits[msg.sender] += amount;

        emit Deposit(msg.sender, amount, id);
    }

    // function withraw for user
    function transferTokensForUser(
        uint256 amount,
        uint256 nonce,
        bytes memory serverSig,
        string calldata id
    ) external nonReentrant whenNotPaused {
        address userAddress = msg.sender;

        require(amount <= userDeposits[userAddress], "Insufficient balance");
        require(!usersNonce[userAddress][nonce], "Nonce already used");
        require(
            verifySignature(
                address(this),
                userAddress,
                amount,
                nonce,
                serverSig
            ),
            "Invalid signature from server"
        );

        usersNonce[userAddress][nonce] = true;
        userDeposits[userAddress] -= amount;

        //transfer
        bool sent = tokenERC20.transfer(userAddress, amount);
        require(sent, "Failed to transfer token");

        emit TransferTokensForUser(userAddress, amount, nonce, id);
    }

    function claimToken(
        uint256 amount,
        uint256 nonce,
        bytes memory serverSig,
        string calldata id
    ) external payable nonReentrant whenNotPaused {
        address userAddress = msg.sender;

        require(msg.value == fee, "Not enough fee to claim token");
        require(!usersNonce[userAddress][nonce], "Nonce already used");
        require(!isClaimed[userAddress], "claimed already!");
        require(
            verifySignature(
                address(this),
                msg.sender,
                amount,
                nonce,
                serverSig
            ),
            "Invalid signature from server"
        );

        usersNonce[userAddress][nonce] = true;
        totalTokensClaimed += amount;
        isClaimed[userAddress] = true;

        //transfer
        payable(feeRecipient).transfer(fee);
        bool sent = tokenERC20.transfer(userAddress, amount);
        require(sent, "Failed to transfer token");

        emit ClaimToken(userAddress, amount, nonce, id);
    }

    function getPoolInfo()
        external
        view
        returns (uint256 numTokensInPool, uint256 numTokensClaimed)
    {
        numTokensInPool = tokenERC20.balanceOf(address(this));
        numTokensClaimed = totalTokensClaimed;
    }

    //==================================SIGNATURE==================================
    function verifySignature(
        address from,
        address to,
        uint256 amount,
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
                    amount,
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
}
