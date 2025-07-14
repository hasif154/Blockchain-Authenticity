# Blockchain-Authenticity
A project on identifying counterfeit products using blockchain

# Core Counterfeit Detection System - Step by Step Implementation

## Overview: How It Works

1. **Authentic Product Registration**: Manufacturer registers product on blockchain
2. **QR Code Generation**: Unique QR code created with blockchain reference
3. **Product Scanning**: Consumer scans QR code
4. **Blockchain Verification**: System checks blockchain for authenticity
5. **Result**: Returns AUTHENTIC or COUNTERFEIT

## Step 1: Smart Contract Development

### 1.1 Setup Development Environment

```bash
# Install Node.js and npm
npm install -g hardhat
mkdir counterfeit-detector
cd counterfeit-detector
npm init -y
npm install --save-dev hardhat @nomiclabs/hardhat-ethers ethers
npx hardhat
```

### 1.2 Core Smart Contract (ProductRegistry.sol)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract ProductRegistry {
    struct Product {
        uint256 id;
        string name;
        string brand;
        address manufacturer;
        uint256 productionDate;
        string batchNumber;
        bool isActive;
        uint256 verificationCount;
    }
    
    // Mappings
    mapping(uint256 => Product) public products;
    mapping(address => bool) public authorizedManufacturers;
    mapping(uint256 => mapping(address => uint256)) public verificationHistory;
    
    // Events
    event ProductRegistered(uint256 indexed productId, address indexed manufacturer);
    event ProductVerified(uint256 indexed productId, address indexed verifier, bool isValid);
    event ManufacturerAuthorized(address indexed manufacturer);
    
    // Modifiers
    modifier onlyAuthorized() {
        require(authorizedManufacturers[msg.sender], "Not authorized manufacturer");
        _;
    }
    
    modifier productExists(uint256 _productId) {
        require(products[_productId].manufacturer != address(0), "Product does not exist");
        _;
    }
    
    // Owner (for demo - use proper access control in production)
    address public owner;
    
    constructor() {
        owner = msg.sender;
        authorizedManufacturers[msg.sender] = true;
    }
    
    // Register a new product
    function registerProduct(
        uint256 _productId,
        string memory _name,
        string memory _brand,
        string memory _batchNumber
    ) external onlyAuthorized {
        require(products[_productId].manufacturer == address(0), "Product already exists");
        
        products[_productId] = Product({
            id: _productId,
            name: _name,
            brand: _brand,
            manufacturer: msg.sender,
            productionDate: block.timestamp,
            batchNumber: _batchNumber,
            isActive: true,
            verificationCount: 0
        });
        
        emit ProductRegistered(_productId, msg.sender);
    }
    
    // Verify product authenticity
    function verifyProduct(uint256 _productId) external returns (bool) {
        if (products[_productId].manufacturer == address(0)) {
            emit ProductVerified(_productId, msg.sender, false);
            return false;
        }
        
        if (!products[_productId].isActive) {
            emit ProductVerified(_productId, msg.sender, false);
            return false;
        }
        
        // Update verification count and history
        products[_productId].verificationCount++;
        verificationHistory[_productId][msg.sender] = block.timestamp;
        
        emit ProductVerified(_productId, msg.sender, true);
        return true;
    }
    
    // Get product details
    function getProduct(uint256 _productId) external view returns (
        string memory name,
        string memory brand,
        address manufacturer,
        uint256 productionDate,
        string memory batchNumber,
        bool isActive,
        uint256 verificationCount
    ) {
        Product memory product = products[_productId];
        return (
            product.name,
            product.brand,
            product.manufacturer,
            product.productionDate,
            product.batchNumber,
            product.isActive,
            product.verificationCount
        );
    }
    
    // Authorize manufacturer (only owner)
    function authorizeManufacturer(address _manufacturer) external {
        require(msg.sender == owner, "Only owner can authorize");
        authorizedManufacturers[_manufacturer] = true;
        emit ManufacturerAuthorized(_manufacturer);
    }
    
    // Deactivate product (for recalls, etc.)
    function deactivateProduct(uint256 _productId) external onlyAuthorized productExists(_productId) {
        require(products[_productId].manufacturer == msg.sender, "Only manufacturer can deactivate");
        products[_productId].isActive = false;
    }
}
```

### 1.3 Deploy Script (deploy.js)

```javascript
const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with account:", deployer.address);
    
    const ProductRegistry = await ethers.getContractFactory("ProductRegistry");
    const productRegistry = await ProductRegistry.deploy();
    
    await productRegistry.deployed();
    console.log("ProductRegistry deployed to:", productRegistry.address);
    
    // Save contract address for later use
    const fs = require('fs');
    const contractAddress = {
        productRegistry: productRegistry.address
    };
    fs.writeFileSync('contract-address.json', JSON.stringify(contractAddress, null, 2));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
```

## Step 2: Backend API Development

### 2.1 Setup Node.js Backend

```bash
mkdir backend
cd backend
npm init -y
npm install express ethers qrcode crypto cors dotenv
```

### 2.2 Core Backend (server.js)

```javascript
const express = require('express');
const { ethers } = require('ethers');
const QRCode = require('qrcode');
const crypto = require('crypto');
const cors = require('cors');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

// Contract ABI (simplified for core functions)
const CONTRACT_ABI = [
    "function registerProduct(uint256 _productId, string memory _name, string memory _brand, string memory _batchNumber) external",
    "function verifyProduct(uint256 _productId) external returns (bool)",
    "function getProduct(uint256 _productId) external view returns (string memory, string memory, address, uint256, string memory, bool, uint256)"
];

// Blockchain setup
const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL || 'http://localhost:8545');
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
const contractAddress = process.env.CONTRACT_ADDRESS;
const contract = new ethers.Contract(contractAddress, CONTRACT_ABI, wallet);

// Generate unique product ID
function generateProductId() {
    return crypto.randomBytes(32).toString('hex');
}

// Register product endpoint
app.post('/api/register-product', async (req, res) => {
    try {
        const { name, brand, batchNumber } = req.body;
        
        // Generate unique product ID
        const productId = generateProductId();
        const productIdHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(productId));
        const productIdNumber = ethers.BigNumber.from(productIdHash);
        
        // Register on blockchain
        const tx = await contract.registerProduct(
            productIdNumber,
            name,
            brand,
            batchNumber
        );
        
        await tx.wait();
        
        // Generate QR code
        const qrData = JSON.stringify({
            productId: productId,
            contractAddress: contractAddress,
            network: 'polygon-mumbai' // or your network
        });
        
        const qrCode = await QRCode.toDataURL(qrData);
        
        res.json({
            success: true,
            productId: productId,
            transactionHash: tx.hash,
            qrCode: qrCode
        });
        
    } catch (error) {
        console.error('Registration error:', error);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// Verify product endpoint
app.post('/api/verify-product', async (req, res) => {
    try {
        const { productId } = req.body;
        
        if (!productId) {
            return res.status(400).json({
                success: false,
                error: 'Product ID is required'
            });
        }
        
        // Convert product ID to blockchain format
        const productIdHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(productId));
        const productIdNumber = ethers.BigNumber.from(productIdHash);
        
        // Get product details from blockchain
        const productDetails = await contract.getProduct(productIdNumber);
        
        // Check if product exists
        if (productDetails[2] === ethers.constants.AddressZero) {
            return res.json({
                success: false,
                authentic: false,
                message: 'Product not found - COUNTERFEIT',
                details: null
            });
        }
        
        // Check if product is active
        if (!productDetails[5]) {
            return res.json({
                success: false,
                authentic: false,
                message: 'Product deactivated - COUNTERFEIT or RECALLED',
                details: null
            });
        }
        
        // Product is authentic
        // Update verification count on blockchain
        const verifyTx = await contract.verifyProduct(productIdNumber);
        await verifyTx.wait();
        
        res.json({
            success: true,
            authentic: true,
            message: 'Product is AUTHENTIC',
            details: {
                name: productDetails[0],
                brand: productDetails[1],
                manufacturer: productDetails[2],
                productionDate: new Date(productDetails[3].toNumber() * 1000).toISOString(),
                batchNumber: productDetails[4],
                verificationCount: productDetails[6].toNumber() + 1
            }
        });
        
    } catch (error) {
        console.error('Verification error:', error);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// QR Code scanning endpoint
app.post('/api/scan-qr', async (req, res) => {
    try {
        const { qrData } = req.body;
        
        let parsedData;
        try {
            parsedData = JSON.parse(qrData);
        } catch (e) {
            return res.status(400).json({
                success: false,
                error: 'Invalid QR code format'
            });
        }
        
        if (!parsedData.productId) {
            return res.status(400).json({
                success: false,
                error: 'QR code does not contain product ID'
            });
        }
        
        // Verify the product using the extracted ID
        const verificationResult = await fetch(`http://localhost:3000/api/verify-product`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                productId: parsedData.productId
            })
        });
        
        const result = await verificationResult.json();
        res.json(result);
        
    } catch (error) {
        console.error('QR scan error:', error);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// Health check endpoint
app.get('/api/health', (req, res) => {
    res.json({ status: 'OK', timestamp: new Date().toISOString() });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});
```

### 2.3 Environment Variables (.env)

```env
RPC_URL=https://polygon-mumbai.g.alchemy.com/v2/YOUR_API_KEY
PRIVATE_KEY=your_private_key_here
CONTRACT_ADDRESS=your_deployed_contract_address
PORT=3000
```

## Step 3: Simple Frontend for Testing

### 3.1 Basic HTML Interface (index.html)

```html
<!DOCTYPE html>
<html>
<head>
    <title>Counterfeit Detection System</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
        .section { margin: 20px 0; padding: 20px; border: 1px solid #ddd; border-radius: 5px; }
        .result { padding: 10px; margin: 10px 0; border-radius: 5px; }
        .authentic { background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .counterfeit { background-color: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        input, button { padding: 10px; margin: 5px; }
        button { background-color: #007bff; color: white; border: none; border-radius: 3px; cursor: pointer; }
        button:hover { background-color: #0056b3; }
    </style>
</head>
<body>
    <h1>Counterfeit Detection System</h1>
    
    <!-- Product Registration Section -->
    <div class="section">
        <h2>Register Product (Manufacturer)</h2>
        <input type="text" id="productName" placeholder="Product Name" />
        <input type="text" id="brandName" placeholder="Brand Name" />
        <input type="text" id="batchNumber" placeholder="Batch Number" />
        <button onclick="registerProduct()">Register Product</button>
        <div id="registrationResult"></div>
    </div>
    
    <!-- QR Code Scanner Section -->
    <div class="section">
        <h2>Scan QR Code (Consumer)</h2>
        <textarea id="qrInput" placeholder="Paste QR code data here..." rows="4" cols="50"></textarea>
        <br>
        <button onclick="scanQR()">Scan QR Code</button>
        <div id="scanResult"></div>
    </div>
    
    <!-- Manual Verification Section -->
    <div class="section">
        <h2>Manual Verification</h2>
        <input type="text" id="productId" placeholder="Product ID" />
        <button onclick="verifyProduct()">Verify Product</button>
        <div id="verificationResult"></div>
    </div>

    <script>
        const API_BASE = 'http://localhost:3000/api';
        
        async function registerProduct() {
            const name = document.getElementById('productName').value;
            const brand = document.getElementById('brandName').value;
            const batchNumber = document.getElementById('batchNumber').value;
            
            if (!name || !brand || !batchNumber) {
                alert('Please fill all fields');
                return;
            }
            
            try {
                const response = await fetch(`${API_BASE}/register-product`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ name, brand, batchNumber })
                });
                
                const result = await response.json();
                
                if (result.success) {
                    document.getElementById('registrationResult').innerHTML = `
                        <div class="result authentic">
                            <h3>Product Registered Successfully!</h3>
                            <p><strong>Product ID:</strong> ${result.productId}</p>
                            <p><strong>Transaction Hash:</strong> ${result.transactionHash}</p>
                            <p><strong>QR Code:</strong></p>
                            <img src="${result.qrCode}" alt="QR Code" />
                        </div>
                    `;
                } else {
                    document.getElementById('registrationResult').innerHTML = `
                        <div class="result counterfeit">
                            <h3>Registration Failed</h3>
                            <p>${result.error}</p>
                        </div>
                    `;
                }
            } catch (error) {
                console.error('Error:', error);
                document.getElementById('registrationResult').innerHTML = `
                    <div class="result counterfeit">
                        <h3>Error</h3>
                        <p>${error.message}</p>
                    </div>
                `;
            }
        }
        
        async function scanQR() {
            const qrData = document.getElementById('qrInput').value;
            
            if (!qrData) {
                alert('Please enter QR code data');
                return;
            }
            
            try {
                const response = await fetch(`${API_BASE}/scan-qr`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ qrData })
                });
                
                const result = await response.json();
                displayVerificationResult(result, 'scanResult');
                
            } catch (error) {
                console.error('Error:', error);
                document.getElementById('scanResult').innerHTML = `
                    <div class="result counterfeit">
                        <h3>Error</h3>
                        <p>${error.message}</p>
                    </div>
                `;
            }
        }
        
        async function verifyProduct() {
            const productId = document.getElementById('productId').value;
            
            if (!productId) {
                alert('Please enter product ID');
                return;
            }
            
            try {
                const response = await fetch(`${API_BASE}/verify-product`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ productId })
                });
                
                const result = await response.json();
                displayVerificationResult(result, 'verificationResult');
                
            } catch (error) {
                console.error('Error:', error);
                document.getElementById('verificationResult').innerHTML = `
                    <div class="result counterfeit">
                        <h3>Error</h3>
                        <p>${error.message}</p>
                    </div>
                `;
            }
        }
        
        function displayVerificationResult(result, elementId) {
            const resultClass = result.authentic ? 'authentic' : 'counterfeit';
            const status = result.authentic ? 'AUTHENTIC' : 'COUNTERFEIT';
            
            let html = `
                <div class="result ${resultClass}">
                    <h3>Product Status: ${status}</h3>
                    <p>${result.message}</p>
            `;
            
            if (result.details) {
                html += `
                    <h4>Product Details:</h4>
                    <p><strong>Name:</strong> ${result.details.name}</p>
                    <p><strong>Brand:</strong> ${result.details.brand}</p>
                    <p><strong>Manufacturer:</strong> ${result.details.manufacturer}</p>
                    <p><strong>Production Date:</strong> ${new Date(result.details.productionDate).toLocaleDateString()}</p>
                    <p><strong>Batch Number:</strong> ${result.details.batchNumber}</p>
                    <p><strong>Verification Count:</strong> ${result.details.verificationCount}</p>
                `;
            }
            
            html += '</div>';
            document.getElementById(elementId).innerHTML = html;
        }
    </script>
</body>
</html>
```

## Step 4: Deployment Instructions

### 4.1 Deploy Smart Contract

```bash
# In your project root
npx hardhat compile
npx hardhat run scripts/deploy.js --network mumbai
```

### 4.2 Configure Environment

```bash
# Copy the deployed contract address to your .env file
echo "CONTRACT_ADDRESS=your_deployed_address_here" >> .env
```

### 4.3 Start Backend

```bash
cd backend
npm start
```

### 4.4 Test the System

1. Open `index.html` in a browser
2. Register a product as a manufacturer
3. Copy the generated QR code data
4. Scan the QR code to verify authenticity
5. Try scanning with invalid data to see counterfeit detection

## Step 5: Testing Scenarios

### Test Case 1: Authentic Product
```javascript
// Register product
POST /api/register-product
{
    "name": "iPhone 14",
    "brand": "Apple",
    "batchNumber": "BATCH001"
}

// Verify product (should return authentic)
POST /api/verify-product
{
    "productId": "generated_product_id"
}
```

### Test Case 2: Counterfeit Product
```javascript
// Try to verify non-existent product
POST /api/verify-product
{
    "productId": "fake_product_id"
}
// Should return counterfeit
```

### Test Case 3: QR Code Scanning
```javascript
// Scan valid QR code
POST /api/scan-qr
{
    "qrData": "{\"productId\":\"real_id\",\"contractAddress\":\"0x...\",\"network\":\"polygon-mumbai\"}"
}
// Should return authentic

// Scan invalid QR code
POST /api/scan-qr
{
    "qrData": "invalid_qr_data"
}
// Should return error
```

## Key Features Implemented

1. **Blockchain Registration**: Products are registered on-chain with immutable records
2. **Unique ID Generation**: Each product gets a cryptographically secure unique ID
3. **QR Code Integration**: QR codes contain product ID and blockchain reference
4. **Instant Verification**: Real-time blockchain queries for authenticity
5. **Counterfeit Detection**: Non-existent or deactivated products are flagged as counterfeit
6. **Verification Tracking**: Count of how many times a product has been verified

## What Happens When Someone Scans:

1. **QR Code Scanned** → Extract product ID
2. **Blockchain Query** → Check if product exists and is active
3. **Result**:
   - **If found + active** → AUTHENTIC
   - **If not found** → COUNTERFEIT
   - **If deactivated** → COUNTERFEIT/RECALLED

This core system provides the foundation for detecting counterfeit products using blockchain technology. The system is secure, fast, and cost-effective for basic verification needs.
