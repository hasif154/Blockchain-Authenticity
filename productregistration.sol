#product registration code solidity

contract ProductRegistry {
    struct Product {
        uint256 id;
        string name;
        string description;
        address manufacturer;
        uint256 timestamp;
        string metadataHash;
        bool isActive;
    }
    
    mapping(uint256 => Product) public products;
    mapping(address => bool) public authorizedManufacturers;
    
    function registerProduct(
        string memory name,
        string memory description,
        string memory metadataHash
    ) external;
    
    function verifyProduct(uint256 productId) external view returns (bool);
    function transferOwnership(uint256 productId, address newOwner) external;
}
