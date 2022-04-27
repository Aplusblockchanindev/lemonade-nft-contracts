pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
//SPDX-License-Identifier: MIT

/// @notice Thrown when completing the transaction results in overallocation of LemonApe Stands.
error MintedOut();
/// @notice Thrown when a user is trying to upgrade a stand, but does not have the previous stand in the upgrade flow.
error MissingPerviousStand();
/// @notice Thrown when completing the transaction results in overallocation of LemonApe Stands.
error Gen0_MintedOut();
/// @notice Thrown when completing the transaction results in overallocation of LemonApe Stands.
error Gen1_MintedOut();
/// @notice Thrown when the dutch auction phase has not yet started, or has already ended.
error MintNotStarted();
/// @notice Thrown when the user has already minted two LemonApe Stands in the dutch auction.
error MintingTooMany();
/// @notice Thrown when the value of the transaction is not enough for the current dutch auction or mintlist price.
error ValueTooLow();
/// @notice Thrown when a user is trying to upgrade past the highest stand level.
error UnknownUpgrade();

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
}

abstract contract ERC721 {
    /*///////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    event Approval(address indexed owner, address indexed spender, uint256 indexed id);

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /*///////////////////////////////////////////////////////////////
                          METADATA STORAGE/LOGIC
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    function tokenURI(uint256 id) public view virtual returns (string memory);

    /*///////////////////////////////////////////////////////////////
                            ERC721 STORAGE                        
    //////////////////////////////////////////////////////////////*/

    uint256 public totalSupply;

    /// @notice The current price to mint a Lemon Stand
    uint256 public currentLemonStandPrice;

    mapping(address => uint256) public balanceOf;

    mapping(uint256 => address) public ownerOf;

    mapping(uint256 => address) public getApproved;

    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /*///////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /*///////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 id) public virtual {
        address owner = ownerOf[id];

        require(msg.sender == owner || isApprovedForAll[owner][msg.sender], "NOT_AUTHORIZED");

        getApproved[id] = spender;

        emit Approval(owner, spender, id);
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        require(from == ownerOf[id], "WRONG_FROM");

        require(to != address(0), "INVALID_RECIPIENT");

        require(
            msg.sender == from || msg.sender == getApproved[id] || isApprovedForAll[from][msg.sender],
            "NOT_AUTHORIZED"
        );

        // Underflow of the sender's balance is impossible because we check for
        // ownership above and the recipient's balance can't realistically overflow.
        unchecked {
            balanceOf[from]--;

            balanceOf[to]++;
        }

        ownerOf[id] = to;

        delete getApproved[id];

        emit Transfer(from, to, id);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        transferFrom(from, to, id);

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, "") ==
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes memory data
    ) public virtual {
        transferFrom(from, to, id);

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, data) ==
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    /*///////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }
}

/// @notice A generic interface for a contract which properly accepts ERC721 tokens.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC721.sol)
interface ERC721TokenReceiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 id,
        bytes calldata data
    ) external returns (bytes4);
}

/// @title Generation 0 and 1 LemonApeStand NFTs
contract LemonApeStandNFT is ERC721, Ownable {
    using Strings for uint256;

    /*///////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Determines the order of the species for each tokenId, mechanism for choosing starting index explained post mint, explanation hash: acb427e920bde46de95103f14b8e57798a603abcf87ff9d4163e5f61c6a56881.
    uint constant public provenanceHash = 0x9912e067bd3802c3b007ce40b6c125160d2ccb5352d199e20c092fdc17af8057;

    /// @dev Sole receiver of collected contract $LAS
    address constant stakingContract = 0xF6BD9Fc094F7aB74a846E5d82a822540EE6c6971;

    /// @dev Address of $LAS to mint Lemon Stands
    address private lasToken = 0xF6BD9Fc094F7aB74a846E5d82a822540EE6c6971;

    /// @dev Address of $POTION to mint higher tier stands
    address private potionToken = 0xF6BD9Fc094F7aB74a846E5d82a822540EE6c6971;

    /// @dev 5000 total nfts can ever be made
    uint constant mintSupply = 5000;

    /// @dev The offsets are the tokenIds that the corresponding evolution stage will begin minting at.
    uint constant grapeStandOffset = 2550;
    uint constant dragonStandOffset = grapeStandOffset + 1500;
    uint constant fourTwentyStandOffset = dragonStandOffset + 725;

    /*///////////////////////////////////////////////////////////////
                        EVOLUTIONARY STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev The next tokenID to be minted for each of the stand stages
    uint gen0_LemonStandSupply; //totalSupply 300
    uint gen1_LemonStandSupply; //totalSupply 2250
    uint grapeStandSupply; //totalSupply 1500
    uint dragonStandSupply; //totalSupply 725
    uint fourTwentyStandSupply; //totalSupply 225

    /*///////////////////////////////////////////////////////////////
                            MINT STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @notice The timestamp the minting for Lemon Stands started
    uint256 public mintStartTime;

    /// @notice The timestamp of the last time a Lemon Stand was minted
    uint256 public lastTimeMinted;

    /// @notice The current generation mint phase
    bool public isGen0Mint;

    /// @notice Starting price of the Lemon Stand in $LAS (1,000 $LAS)
    uint256 constant public startPrice = 1000000000000;

    /*///////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public baseURI;

    /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys the contract, minting 330 Pixelmon to the Gnosis Safe and setting the initial metadata URI.
    constructor(string memory _baseURI) ERC721("LEMONAPESTAND NFT", "LASNFT") {
        baseURI = _baseURI;
        unchecked {
            balanceOf[msg.sender] += 330;
            totalSupply += 330;
            for (uint256 i = 0; i < 330; i++) {
                ownerOf[i] = msg.sender;
                emit Transfer(address(0), msg.sender, i);
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                            METADATA LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows the contract deployer to set the metadata URI.
    /// @param _baseURI The new metadata URI.
    function setBaseURI(string memory _baseURI) public onlyOwner {
        baseURI = _baseURI;
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return string(abi.encodePacked(baseURI, id.toString()));
    }

    /*///////////////////////////////////////////////////////////////
                        REVERSE-DUTCH AUCTION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates the mint price with the accumulated rate deduction since the mint's started. Every hour there is no mint the price goes down 100 tokens. After every mint the price goes up 100 tokens.
    /// @return The mint price at the current time, or 0 if the deductions are greater than the mint's start price.
    function getCurrentTokenPrice() private view returns (uint) {
        uint priceReduction = ((block.timestamp - lastTimeMinted) / 1 hours) * 100000000000;
        return currentLemonStandPrice >= priceReduction ? (currentLemonStandPrice - priceReduction) : 100000000000;
    }

    /// @notice Purchases a Pixelmon NFT in the dutch auction
    /// @param mintingTwo True if the user is minting two Pixelmon, otherwise false.
    /// @dev balanceOf is fine, team is aware and accepts that transferring out and repurchasing can be done, even by contracts. 
    function mint(bool mintingTwo) public {
        if(block.timestamp < mintStartTime) revert MintNotStarted();

        uint count = mintingTwo ? 2 : 1;
        uint price = getCurrentTokenPrice();

        if(totalSupply + count > mintSupply) revert Gen0_MintedOut();
        if(totalSupply + count > mintSupply) revert Gen1_MintedOut();
        if(balanceOf[msg.sender] + count > 2) revert MintingTooMany();
        if(IERC20(lasToken).balanceOf(msg.sender) < price * count) revert ValueTooLow();

        mintingTwo ? _mintTwo(msg.sender) : _mint(msg.sender, totalSupply);
    }

    /*///////////////////////////////////////////////////////////////
                       INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 id) internal virtual {
        require(to != address(0), "INVALID_RECIPIENT");

        require(ownerOf[id] == address(0), "ALREADY_MINTED");
        IERC20(lasToken).transfer(stakingContract, currentLemonStandPrice);
        // Counter overflow is incredibly unrealistic.
        unchecked {
            totalSupply++;

            balanceOf[to]++;
        }

        ownerOf[id] = to;

        emit Transfer(address(0), to, id);
        currentLemonStandPrice += 100000000000;
    }

    /// @notice Mints two Pixelmons to an address
    /// @param to Receiver of the two newly minted NFTs
    /// @dev errors taken from super._mint
    function _mintTwo(address to) internal {
        require(to != address(0), "INVALID_RECIPIENT");
        require(ownerOf[totalSupply] == address(0), "ALREADY_MINTED");
        uint currentId = totalSupply;
        IERC20(lasToken).transfer(stakingContract, currentLemonStandPrice * 2);
        /// @dev unchecked because no arithmetic can overflow
        unchecked {
            totalSupply += 2;
            balanceOf[to] += 2;
            ownerOf[currentId] = to;
            ownerOf[currentId + 1] = to;
            emit Transfer(address(0), to, currentId);
            emit Transfer(address(0), to, currentId + 1);
        }
        currentLemonStandPrice += 200000000000;
    }

    /*///////////////////////////////////////////////////////////////
                        UPGRADE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints an upgraded LemonApe Stand
    /// @param receiver Receiver of the upgraded LemonApe Stand
    /// @param standIdToUpgrade The evolution (2-4) that the Pixelmon is undergoing
    function mintUpgradedStand(address receiver, uint standIdToUpgrade) public {
        uint upgradeToStand;
        if(standIdToUpgrade <= 2550){
            upgradeToStand = 2;
        } else if(standIdToUpgrade <= 4050){
            upgradeToStand = 3;
        } else if(standIdToUpgrade <= 4999){
            upgradeToStand = 4;
        } else {
            revert UnknownUpgrade();
        }

        if (upgradeToStand == 2) {
            if(grapeStandSupply >= 1500) revert MintedOut();
            if(IERC20(potionToken).balanceOf(msg.sender) < 1) revert ValueTooLow();
            IERC20(potionToken).transfer(stakingContract, 1);
            _mint(receiver, grapeStandOffset + grapeStandSupply);
            unchecked {
                grapeStandSupply++;
            }
        } else if (upgradeToStand == 3) {
            if(dragonStandSupply >= 725) revert MintedOut();
            if(IERC20(potionToken).balanceOf(msg.sender) < 2) revert ValueTooLow();
            IERC20(potionToken).transfer(stakingContract, 2);
            _mint(receiver, dragonStandOffset + dragonStandSupply);
            unchecked {
                dragonStandSupply++;
            }
        } else if (upgradeToStand == 4) {
            if(fourTwentyStandSupply >= 225) revert MintedOut();
            if(IERC20(potionToken).balanceOf(msg.sender) < 3) revert ValueTooLow();
            IERC20(potionToken).transfer(stakingContract, 3);
            _mint(receiver, fourTwentyStandOffset + fourTwentyStandSupply);
            unchecked {
                fourTwentyStandSupply++;
            }
        } else  {
            revert UnknownUpgrade();
        }
    }
}
