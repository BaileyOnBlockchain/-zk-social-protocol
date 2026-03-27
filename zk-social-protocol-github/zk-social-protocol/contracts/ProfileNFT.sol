// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title ProfileNFT
 * @notice Soulbound-style profile NFTs — one per address, metadata stored on IPFS
 * @dev ERC721 with URI storage and enumerable extension.
 *      Mint price configurable by owner. Metadata updatable by token holder.
 */
contract ProfileNFT is ERC721, ERC721URIStorage, ERC721Enumerable, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // ─── State ────────────────────────────────────────────────────────────────

    uint256 private _tokenIdCounter;
    uint256 public mintPrice;

    mapping(address => uint256) public addressToTokenId;
    mapping(uint256 => address) public tokenIdToAddress;
    mapping(uint256 => string)  public tokenMetadata;   // tokenId => IPFS URI

    // ─── Events ───────────────────────────────────────────────────────────────

    event ProfileMinted(address indexed owner, uint256 indexed tokenId, string metadataURI);
    event MetadataUpdated(uint256 indexed tokenId, string newMetadataURI);
    event MintPriceUpdated(uint256 oldPrice, uint256 newPrice);

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor(uint256 _mintPrice) ERC721("Profile NFT", "PROFILE") Ownable(msg.sender) {
        mintPrice = _mintPrice;
    }

    // ─── Minting ──────────────────────────────────────────────────────────────

    /**
     * @notice Mint a profile NFT (one per address)
     * @param metadataURI IPFS URI pointing to profile JSON
     */
    function mintProfile(string memory metadataURI) external payable nonReentrant {
        require(msg.value >= mintPrice,               "ProfileNFT: Insufficient payment");
        require(addressToTokenId[msg.sender] == 0,    "ProfileNFT: Already minted");

        uint256 tokenId = _tokenIdCounter++;
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, metadataURI);

        addressToTokenId[msg.sender]  = tokenId;
        tokenIdToAddress[tokenId]     = msg.sender;
        tokenMetadata[tokenId]        = metadataURI;

        emit ProfileMinted(msg.sender, tokenId, metadataURI);
    }

    /**
     * @notice Update profile metadata (token owner only)
     * @param tokenId       Token to update
     * @param newMetadataURI New IPFS URI
     */
    function updateMetadata(uint256 tokenId, string memory newMetadataURI) external {
        require(ownerOf(tokenId) == msg.sender, "ProfileNFT: Not owner");
        tokenMetadata[tokenId] = newMetadataURI;
        _setTokenURI(tokenId, newMetadataURI);
        emit MetadataUpdated(tokenId, newMetadataURI);
    }

    // ─── Owner ────────────────────────────────────────────────────────────────

    function setMintPrice(uint256 _newPrice) external onlyOwner {
        emit MintPriceUpdated(mintPrice, _newPrice);
        mintPrice = _newPrice;
    }

    function withdraw() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "ProfileNFT: Withdraw failed");
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    function getTokenId(address user)      external view returns (uint256) { return addressToTokenId[user]; }
    function getAddress(uint256 tokenId)   external view returns (address) { return tokenIdToAddress[tokenId]; }

    // ─── Overrides ────────────────────────────────────────────────────────────

    function _update(address to, uint256 tokenId, address auth)
        internal override(ERC721, ERC721Enumerable) returns (address)
    { return super._update(to, tokenId, auth); }

    function _increaseBalance(address account, uint128 value)
        internal override(ERC721, ERC721Enumerable)
    { super._increaseBalance(account, value); }

    function tokenURI(uint256 tokenId)
        public view override(ERC721, ERC721URIStorage) returns (string memory)
    { return super.tokenURI(tokenId); }

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721, ERC721Enumerable, ERC721URIStorage) returns (bool)
    { return super.supportsInterface(interfaceId); }
}
