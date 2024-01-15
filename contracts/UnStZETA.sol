// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";

import "./interfaces/IUnStZETA.sol";
import "./interfaces/IStZETA.sol";

contract UnStZETA is 
    IUnStZETA,
    OwnableUpgradeable,
    ERC721Upgradeable,
    ERC721PausableUpgradeable
{
    /// @notice stZETA address.
    address public stZETA;

    /// @notice tokenId index.
    uint256 public tokenIdIndex;

    /// @notice Version.
    string public version;

    /// @notice Map addresses to owned token arrays.
    mapping(address => uint256[]) public owner2Tokens;

    /// @notice TokenId exists only in one of these arrays since a token can only be owned by one address at a time.
    /// This mapping stores the index of tokenId in one of these arrays.
    mapping(uint256 => uint256) public token2Index;

    /// @notice Map addresses to approved token arrays.
    mapping(address => uint256[]) public address2Approved;

    /// @notice TokenId exists only in one of these arrays since a token can only be approved to one address at a time.
    /// This mapping stores the index of tokenId in one of these arrays.
    mapping(uint256 => uint256) public tokenId2ApprovedIndex;

    /// @notice Modifier that can only be called by the stZETA contract.
    modifier isStZETA() {
        require(msg.sender == stZETA, "not stZETA");
        _;
    }

    /// @notice Initialization function.
    function initialize(string memory name_, string memory symbol_, address _stZETA) external initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __Ownable_init_unchained();
        __ERC721_init_unchained(name_, symbol_);
        __Pausable_init_unchained();
        __ERC721Pausable_init_unchained();

        // Set stZETA contract address.
        stZETA = _stZETA;
        // Set version.
        version = "1.0.2";
    }

    /// @notice Increase token supply and mint token based on the index.
    /// @param _to - Address that will own the minted token.
    /// @return Index of the minted token.
    function mint(address _to) external override isStZETA returns (uint256) {
        _mint(_to, ++tokenIdIndex);
        return tokenIdIndex;
    }

    /// @notice Burn the token with the specified _tokenId.
    /// @param _tokenId - ID of the token to be burned.
    function burn(uint256 _tokenId) external override isStZETA {
        _burn(_tokenId);
    }

    /// @notice Override the approve function.
    /// @param _to - Address to approve the token to.
    /// @param _tokenId - ID of the token to be approved to _to.
    function approve(address _to, uint256 _tokenId)
        public
        override(ERC721Upgradeable, IERC721Upgradeable) {
        // If this token was approved before, remove it from the mapping of approvals.
        address approvedAddress = getApproved(_tokenId);
        if (approvedAddress != address(0)) {
            _removeApproval(_tokenId, approvedAddress);
        }
        // Call the approve function of the parent class.
        super.approve(_to, _tokenId);
        // Get the approved token array.
        uint256[] storage approvedTokens = address2Approved[_to];

        // Add the new approved token to the mapping.
        approvedTokens.push(_tokenId);
        tokenId2ApprovedIndex[_tokenId] = approvedTokens.length - 1;
    }

    /// @notice TODO: Override _beforeTokenTransfer.
    /// @param from - Owner of the token.
    /// @param to - Receiver of the token.
    /// @param tokenId - ID of the token.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    )
        internal
        virtual
        override(ERC721Upgradeable, ERC721PausableUpgradeable)
        whenNotPaused {
        // Check if from and to are different.
        require(from != to, "Invalid operation");
        // Call the _beforeTokenTransfer function of the parent class.
        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        // Minting
        if (from == address(0)) {
            // Get the owner's token array.
            uint256[] storage ownerTokens = owner2Tokens[to];
            // Add the token to the owner's token array.
            ownerTokens.push(tokenId);
            token2Index[tokenId] = ownerTokens.length - 1;
        }
        // Burning
        else if (to == address(0)) {
            // Get the owner's token array.
            uint256[] storage ownerTokens = owner2Tokens[from];
            // Get the length of the owner's token array.
            uint256 ownerTokensLength = ownerTokens.length;
            // Get the index of the token in the owner's token array.
            uint256 burnedTokenIndexInOwnerTokens = token2Index[tokenId];
            // Get the index of the last token in the owner's token array.
            uint256 lastOwnerTokensIndex = ownerTokensLength - 1;
            // If the token to be burned is not the last token in the owner's token array.
            if (
                burnedTokenIndexInOwnerTokens != lastOwnerTokensIndex &&
                ownerTokensLength != 1
            ) {
                uint256 lastOwnerTokenId = ownerTokens[lastOwnerTokensIndex];
                // Make the last token have the index of the token we want to burn.
                // So when we request the index of the token with the id of the current last token in ownerTokens,
                // it doesn't point to the last slot in ownerTokens, but to the slot of the burned token (which we will update in the next line).
                token2Index[lastOwnerTokenId] = burnedTokenIndexInOwnerTokens;
                // Copy the current last token to the position of the token we want to burn.
                // So the pointer updated in tokenId2Index points to the slot with the correct value.
                ownerTokens[burnedTokenIndexInOwnerTokens] = lastOwnerTokenId;
            }
            ownerTokens.pop();
            delete token2Index[tokenId];

            address approvedAddress = getApproved(tokenId);
            if (approvedAddress != address(0)) {
                _removeApproval(tokenId, approvedAddress);
            }
        }
        // Transferring
        else if (from != to) {
            address approvedAddress = getApproved(tokenId);
            if (approvedAddress != address(0)) {
                _removeApproval(tokenId, approvedAddress);
            }

            uint256[] storage senderTokens = owner2Tokens[from];
            uint256[] storage receiverTokens = owner2Tokens[to];

            uint256 tokenIndex = token2Index[tokenId];

            uint256 ownerTokensLength = senderTokens.length;
            uint256 removeTokenIndexInOwnerTokens = tokenIndex;
            uint256 lastOwnerTokensIndex = ownerTokensLength - 1;

            if (
                removeTokenIndexInOwnerTokens != lastOwnerTokensIndex &&
                ownerTokensLength != 1
            ) {
                uint256 lastOwnerTokenId = senderTokens[lastOwnerTokensIndex];
                // Make the last token have the index of the token we want to burn.
                // So when we request the index of the token with the id of the current last token in ownerTokens,
                // it doesn't point to the last slot in ownerTokens, but to the slot of the burned token (which we will update in the next line).
                token2Index[lastOwnerTokenId] = removeTokenIndexInOwnerTokens;
                // Copy the current last token to the position of the token we want to burn.
                // So the pointer updated in tokenId2Index points to the slot with the correct value.
                senderTokens[removeTokenIndexInOwnerTokens] = lastOwnerTokenId;
            }
            senderTokens.pop();

            receiverTokens.push(tokenId);
            token2Index[tokenId] = receiverTokens.length - 1;
        }
    }

    /// @notice Check if the spender is the owner or if the tokenId has been approved to them.
    /// @param _spender - Address to be checked.
    /// @param _tokenId - Token ID to be checked with _spender.
    function isApprovedOrOwner(address _spender, uint256 _tokenId)
        external
        view
        override
        returns (bool) {
        return _isApprovedOrOwner(_spender, _tokenId);
    }

    /// @notice Set the stZETA contract address.
    /// @param _stZETA - stZETA contract address.
    function setStZETA(address _stZETA) external override onlyOwner {
        stZETA = _stZETA;
    }

    /// @notice Set the version.
    /// @param _version - New version to be set.
    function setVersion(string calldata _version) external override onlyOwner {
        version = _version;
    }

    /// @notice Retrieve the owned token array.
    /// @param _address - Address to retrieve tokens from.
    /// @return - Owned token array.
    function getOwnedTokens(address _address)
        external
        view
        override
        returns (uint256[] memory) {
        return owner2Tokens[_address];
    }

    /// @notice Retrieve the approved token array.
    /// @param _address - Address to retrieve tokens from.
    /// @return - Approved token array.
    function getApprovedTokens(address _address)
        external
        view
        returns (uint256[] memory) {
        return address2Approved[_address];
    }

    /// @notice Remove tokenId from the approved token array of a specific user.
    /// @param _tokenId - ID of the token to be removed.
    function _removeApproval(uint256 _tokenId, address _approvedAddress) internal {
        uint256[] storage approvedTokens = address2Approved[_approvedAddress];
        uint256 removeApprovedTokenIndexInOwnerTokens = tokenId2ApprovedIndex[
            _tokenId
        ];
        uint256 approvedTokensLength = approvedTokens.length;
        uint256 lastApprovedTokensIndex = approvedTokensLength - 1;

        if (
            removeApprovedTokenIndexInOwnerTokens != lastApprovedTokensIndex &&
            approvedTokensLength != 1
        ) {
            uint256 lastApprovedTokenId = approvedTokens[
                lastApprovedTokensIndex
            ];
            // Make the last token have the index of the token we want to burn.
            // So when we request the index of the token with the id of the current last token in approveTokens,
            // it doesn't point to the last slot in approveTokens, but to the slot of the burned token (which we will update in the next line).
            tokenId2ApprovedIndex[
                lastApprovedTokenId
            ] = removeApprovedTokenIndexInOwnerTokens;
            // Copy the current last token to the position of the token we want to burn.
            // So the pointer updated in tokenId2ApprovedIndex points to the slot with the correct value.
            approvedTokens[
                removeApprovedTokenIndexInOwnerTokens
            ] = lastApprovedTokenId;
        }

        approvedTokens.pop();
        delete tokenId2ApprovedIndex[_tokenId];
    }

    /// @notice Toggle the pause status.
    function togglePause() external override onlyOwner {
        paused() ? _unpause() : _pause();
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        // Query the current epoch.
        uint256 currentEpoch = IStZETA(stZETA).currentEpoch();
        // Query the epoch of this tokenId.
        uint256 tokenIdEpoch = IStZETA(stZETA).getTokenIdEpoch(tokenId);

        return tokenIdEpoch <= currentEpoch ? "https://src.zetaearn.com/nft/nft_completed.json" : "https://src.zetaearn.com/nft/nft_pending.json";
    }

    /// @notice Get the version for each update.
    function getUpdateVersion() external pure override returns(string memory) {
        return "1.0.2.3";
    }

}