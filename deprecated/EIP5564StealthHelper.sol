// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./FUMVault.sol";

/// @title EIP-5564 Stealth Address Helper for FUM Vault
/// @notice Helper contract demonstrating complete EIP-5564 stealth address workflow
/// @dev This contract shows how to properly generate and use stealth addresses with FUM Vault
contract EIP5564StealthHelper {
    
    FUMVault public immutable fumVault;
    
    /// @notice EIP-5564 scheme ID for SECP256k1 with view tags
    uint256 public constant SCHEME_ID = 1;
    
    // =============================================================
    //                           EVENTS
    // =============================================================
    
    /// @notice Emitted when a stealth meta-address is registered
    event StealthMetaAddressRegistered(
        address indexed user,
        bytes spendingPubKey,
        bytes viewingPubKey,
        string stealthMetaAddress
    );
    
    /// @notice Emitted when a vault is created with stealth address
    event StealthVaultCreated(
        uint256 indexed vaultId,
        address indexed stealthAddress,
        bytes ephemeralPubKey,
        bytes1 viewTag,
        address indexed creator
    );
    
    // =============================================================
    //                           STORAGE
    // =============================================================
    
    /// @notice Mapping from user to their stealth meta-address
    mapping(address => bytes) public userStealthMetaAddress;
    
    /// @notice Mapping from user to their spending public key
    mapping(address => bytes) public userSpendingPubKey;
    
    /// @notice Mapping from user to their viewing public key
    mapping(address => bytes) public userViewingPubKey;
    
    // =============================================================
    //                        CONSTRUCTOR
    // =============================================================
    
    constructor(address _fumVault) {
        fumVault = FUMVault(_fumVault);
    }
    
    // =============================================================
    //                    STEALTH META-ADDRESS MANAGEMENT
    // =============================================================
    
    /// @notice Register a stealth meta-address for a user
    /// @param _spendingPubKey User's spending public key (33 bytes)
    /// @param _viewingPubKey User's viewing public key (33 bytes)
    function registerStealthMetaAddress(
        bytes memory _spendingPubKey,
        bytes memory _viewingPubKey
    ) external {
        require(_spendingPubKey.length == 33, "Invalid spending public key length");
        require(_viewingPubKey.length == 33, "Invalid viewing public key length");
        
        // Combine spending and viewing public keys
        bytes memory stealthMetaAddress = new bytes(66);
        for (uint256 i = 0; i < 33; i++) {
            stealthMetaAddress[i] = _spendingPubKey[i];
            stealthMetaAddress[i + 33] = _viewingPubKey[i];
        }
        
        userStealthMetaAddress[msg.sender] = stealthMetaAddress;
        userSpendingPubKey[msg.sender] = _spendingPubKey;
        userViewingPubKey[msg.sender] = _viewingPubKey;
        
        // Format as EIP-5564 stealth meta-address string
        string memory stealthMetaAddressString = string(
            abi.encodePacked(
                "st:eth:0x",
                _bytesToHex(_spendingPubKey),
                _bytesToHex(_viewingPubKey)
            )
        );
        
        emit StealthMetaAddressRegistered(
            msg.sender,
            _spendingPubKey,
            _viewingPubKey,
            stealthMetaAddressString
        );
    }
    
    // =============================================================
    //                    STEALTH VAULT CREATION
    // =============================================================
    
    /// @notice Create a time vault with automatically generated stealth address
    /// @param _token Token address (address(0) for ETH)
    /// @param _amount Amount to lock
    /// @param _unlockTime Timestamp when vault unlocks
    /// @param _recipientStealthMetaAddress Recipient's stealth meta-address (66 bytes)
    /// @return vaultId The created vault ID
    function createStealthTimeVault(
        address _token,
        uint256 _amount,
        uint256 _unlockTime,
        bytes memory _recipientStealthMetaAddress
    ) external payable returns (uint256 vaultId) {
        require(_recipientStealthMetaAddress.length == 66, "Invalid stealth meta-address");
        
        // Generate stealth address using FUM Vault's EIP-5564 implementation
        (address stealthAddress, bytes memory ephemeralPubKey, bytes1 viewTag) = 
            fumVault.generateStealthAddress(_recipientStealthMetaAddress);
        
        // Create metadata according to EIP-5564 specification
        bytes memory metadata = _createMetadata(viewTag, _token, _amount);
        
        // Create vault with stealth address
        vaultId = fumVault.createTimeVault{value: msg.value}(
            _token,
            _amount,
            _unlockTime,
            stealthAddress,
            ephemeralPubKey,
            metadata
        );
        
        emit StealthVaultCreated(
            vaultId,
            stealthAddress,
            ephemeralPubKey,
            viewTag,
            msg.sender
        );
    }
    
    // =============================================================
    //                    STEALTH ADDRESS SCANNING
    // =============================================================
    
    /// @notice Scan for vaults belonging to a user using their viewing key
    /// @param _viewingKey User's viewing private key
    /// @param _spendingPubKey User's spending public key
    /// @param _startVaultId Starting vault ID for scanning
    /// @param _limit Maximum number of vaults to scan
    /// @return ownedVaultIds Array of vault IDs owned by the user
    /// @return stealthAddresses Array of corresponding stealth addresses
    function scanForOwnedVaults(
        bytes memory _viewingKey,
        bytes memory _spendingPubKey,
        uint256 _startVaultId,
        uint256 _limit
    ) external view returns (
        uint256[] memory ownedVaultIds,
        address[] memory stealthAddresses
    ) {
        // Get vaults for scanning
        (
            uint256[] memory vaultIds,
            address[] memory vaultStealthAddresses,
            bytes[] memory ephemeralPubKeys,
            bytes1[] memory viewTags
        ) = fumVault.getVaultsForScanning(_startVaultId, _limit);
        
        // Count owned vaults first
        uint256 ownedCount = 0;
        bool[] memory isOwned = new bool[](vaultIds.length);
        
        for (uint256 i = 0; i < vaultIds.length; i++) {
            if (vaultStealthAddresses[i] != address(0)) {
                bool owned = fumVault.checkStealthAddress(
                    vaultStealthAddresses[i],
                    ephemeralPubKeys[i],
                    _viewingKey,
                    _spendingPubKey
                );
                
                if (owned) {
                    isOwned[i] = true;
                    ownedCount++;
                }
            }
        }
        
        // Create result arrays
        ownedVaultIds = new uint256[](ownedCount);
        stealthAddresses = new address[](ownedCount);
        
        uint256 resultIndex = 0;
        for (uint256 i = 0; i < vaultIds.length; i++) {
            if (isOwned[i]) {
                ownedVaultIds[resultIndex] = vaultIds[i];
                stealthAddresses[resultIndex] = vaultStealthAddresses[i];
                resultIndex++;
            }
        }
    }
    
    // =============================================================
    //                    HELPER FUNCTIONS
    // =============================================================
    
    /// @notice Create EIP-5564 compliant metadata
    /// @param _viewTag View tag for efficient scanning
    /// @param _token Token address
    /// @param _amount Token amount
    /// @return metadata The formatted metadata
    function _createMetadata(
        bytes1 _viewTag,
        address _token,
        uint256 _amount
    ) internal pure returns (bytes memory metadata) {
        if (_token == address(0)) {
            // ETH metadata format according to EIP-5564
            metadata = new bytes(57);
            metadata[0] = _viewTag;                    // Byte 1: view tag
            metadata[1] = 0xee; metadata[2] = 0xee;    // Bytes 2-5: 0xeeeeeeee
            metadata[3] = 0xee; metadata[4] = 0xee;
            
            // Bytes 6-25: ETH address (0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
            address ethAddress = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
            bytes20 ethAddressBytes = bytes20(ethAddress);
            for (uint256 i = 0; i < 20; i++) {
                metadata[5 + i] = ethAddressBytes[i];
            }
            
            // Bytes 26-57: amount (32 bytes)
            bytes32 amountBytes = bytes32(_amount);
            for (uint256 i = 0; i < 32; i++) {
                metadata[25 + i] = amountBytes[i];
            }
        } else {
            // ERC-20 metadata format
            metadata = new bytes(57);
            metadata[0] = _viewTag;                    // Byte 1: view tag
            
            // Bytes 2-5: function selector (transfer function)
            bytes4 transferSelector = bytes4(keccak256("transfer(address,uint256)"));
            metadata[1] = transferSelector[0];
            metadata[2] = transferSelector[1];
            metadata[3] = transferSelector[2];
            metadata[4] = transferSelector[3];
            
            // Bytes 6-25: token contract address
            bytes20 tokenAddressBytes = bytes20(_token);
            for (uint256 i = 0; i < 20; i++) {
                metadata[5 + i] = tokenAddressBytes[i];
            }
            
            // Bytes 26-57: amount (32 bytes)
            bytes32 amountBytes = bytes32(_amount);
            for (uint256 i = 0; i < 32; i++) {
                metadata[25 + i] = amountBytes[i];
            }
        }
    }
    
    /// @notice Convert bytes to hex string
    /// @param _bytes Input bytes
    /// @return hex Hex string representation
    function _bytesToHex(bytes memory _bytes) internal pure returns (string memory hex) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(_bytes.length * 2);
        
        for (uint256 i = 0; i < _bytes.length; i++) {
            result[i * 2] = hexChars[uint8(_bytes[i]) >> 4];
            result[i * 2 + 1] = hexChars[uint8(_bytes[i]) & 0x0f];
        }
        
        return string(result);
    }
    
    // =============================================================
    //                    VIEW FUNCTIONS
    // =============================================================
    
    /// @notice Get user's stealth meta-address
    /// @param _user User address
    /// @return stealthMetaAddress The user's stealth meta-address
    function getUserStealthMetaAddress(address _user) external view returns (bytes memory stealthMetaAddress) {
        return userStealthMetaAddress[_user];
    }
    
    /// @notice Get formatted stealth meta-address string
    /// @param _user User address
    /// @return stealthMetaAddressString Formatted EIP-5564 stealth meta-address
    function getFormattedStealthMetaAddress(address _user) external view returns (string memory stealthMetaAddressString) {
        bytes memory stealthMetaAddress = userStealthMetaAddress[_user];
        if (stealthMetaAddress.length == 0) return "";
        
        return string(abi.encodePacked("st:eth:0x", _bytesToHex(stealthMetaAddress)));
    }
}
