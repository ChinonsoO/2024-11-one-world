import { expect } from "chai";
import { ethers } from "hardhat";

const domainType = [
    { name: "name", type: "string" },
    { name: "version", type: "string" },
    { name: "verifyingContract", type: "address" },
    { name: "salt", type: "bytes32" },
];

const metaTransactionType = [
    { name: "nonce", type: "uint256" },
    { name: "from", type: "address" },
    { name: "functionSignature", type: "bytes" },
];

const chainID = 80002;
const salt = '0x' + chainID.toString(16).padStart(64, '0');  // Ensuring 32 bytes padding

const defaultDomainData = {
    name: "OWP",
    version: "1",
    verifyingContract: "0xedE2b6A7f13e7452727a635a71782eF784811CF7",
    salt: ethers.utils.hexZeroPad(salt, 32),  // Ensuring it's 32 bytes long
};

async function signTypedData(signer:any, from:any, data:any) {

    const [method, argData] = ["eth_signTypedData_v4", JSON.stringify(data)]
  
    return await signer.provider.send(method, [from, argData]);
  }

const getTransactionData = async (nonce:any, abi:any, params:any, wallet:any, domainData:any) => {
    const iface = new ethers.utils.Interface([abi]);  // Constructing an interface with the ABI
    const functionSignature = iface.encodeFunctionData(abi.name, params);
    const message = {
        nonce: parseInt(nonce),
        from: wallet.address,
        functionSignature,
    };

    const dataToSign = {
        types: {
            EIP712Domain: domainType,
            MetaTransaction: metaTransactionType,
        },
        domain: domainData,
        primaryType: "MetaTransaction",
        message: message,
    };

    const signature = await signTypedData(wallet, wallet.address, dataToSign);
    const { r, s, v } = ethers.utils.splitSignature(signature);  // Extract r, s, v from signature

    return { r, s, v: v + 27, functionSignature };  // Adjust `v` according to Ethereum transaction standards
};

// Usage example with async function to trigger transaction data getting.
async function example(userAddress:any) {
    const provider = new ethers.providers.JsonRpcProvider('http://localhost:8545');
    const privateKey = '0x...';  // Your wallet's private key
    const wallet = new ethers.Wallet(privateKey, provider);
    const nonce = await wallet.getTransactionCount();

    const abi = {
        inputs: [
            {
                "internalType": "address",
                "name": "to",
                "type": "address"
            },
            {
                "internalType": "uint256",
                "name": "tokenId",
                "type": "uint256"
            },
            {
                "internalType": "uint256",
                "name": "amount",
                "type": "uint256"
            }
        ],
        name: "mint",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function"
    }

    const params = [userAddress, userAddress, 1];  // Example params
    const transactionData = await getTransactionData(nonce, abi, params, wallet, defaultDomainData);
}

describe("MembershipERC1155 Contract", function () {
    let MembershipERC1155:any;
    let membershipERC1155:any;
    let testERC20: any;
    let deployer:any, user:any, anotherUser:any, nonAdmin:any;
    let tokenURI = "https://example.com/{id}.json";

    before(async function () {
        [deployer, user, anotherUser, nonAdmin] = await ethers.getSigners();
        MembershipERC1155 = await ethers.getContractFactory("MembershipERC1155");
    });

    beforeEach(async function () {
        membershipERC1155 = await MembershipERC1155.deploy({ gasLimit: 8_000_000 });
        await membershipERC1155.deployed();
    
        const ERC20 = await ethers.getContractFactory("OWPERC20");
        testERC20 = await ERC20.deploy('OWP', 'OWP', { gasLimit: 8_000_000 });
        await testERC20.deployed();
    
        // Call initialize with the additional currency address
        await membershipERC1155.initialize(
            "TestToken",       // name
            "TST",             // symbol
            tokenURI,          // token URI
            deployer.address,  // deployer or creator
            testERC20.address  // currency address
        );
    });

    describe("Deployment", function () {
        it("Should set the right owner and deployer", async function () {
            expect(await membershipERC1155.deployer()).to.equal(deployer.address);
            expect(await membershipERC1155.creator()).to.equal(deployer.address);
        });

        // it("Should set the right token name and symbol", async function () {
        //     expect(await membershipERC1155.name()).to.equal("TestToken");
        //     expect(await membershipERC1155.symbol()).to.equal("TST");
        // });
    });

    // describe("Token Minting", function () {
    //     it("Should mint tokens successfully", async function () {
    //         await expect(membershipERC1155.connect(deployer).mint(user.address, 1, 100))
    //             .to.emit(membershipERC1155, "TransferSingle");
    //         expect(await membershipERC1155.balanceOf(user.address, 1)).to.equal(100);
    //     });

    //     it("Should fail to mint tokens if not called by OWP_FACTORY_ROLE", async function () {
    //         await expect(membershipERC1155.connect(nonAdmin).mint(user.address, 1, 100))
    //             .to.be.revertedWith("AccessControl: account 0x90f79bf6eb2c4f870365e785982e1f101e93b906 is missing role 0x8b78a73274a0ca608391d82d111f52b8320c4327ef3d42a14e24e41e7622dfd6");
    //     });
    // });

    // describe("Token Burning", function () {
    //     beforeEach(async function () {
    //         await membershipERC1155.connect(deployer).mint(user.address, 1, 100);
    //     });

    //     it("Should burn tokens successfully", async function () {
    //         await expect(membershipERC1155.connect(deployer).burn(user.address, 1, 50))
    //             .to.emit(membershipERC1155, "TransferSingle");
    //         expect(await membershipERC1155.balanceOf(user.address, 1)).to.equal(50);
    //     });

    //     it("Should fail to burn tokens if not called by OWP_FACTORY_ROLE", async function () {
    //         await expect(membershipERC1155.connect(nonAdmin).burn(user.address, 1, 50))
    //             .to.be.revertedWith("AccessControl: account 0x90f79bf6eb2c4f870365e785982e1f101e93b906 is missing role 0x8b78a73274a0ca608391d82d111f52b8320c4327ef3d42a14e24e41e7622dfd6");
    //     });

    //     it("Should burn batch tokens successfully", async function () {
    //         await expect(membershipERC1155.connect(deployer).burnBatch(user.address))
    //             .to.emit(membershipERC1155, "TransferSingle");
    //         expect(await membershipERC1155.balanceOf(user.address, 1)).to.equal(0);
    //     });

    //     it("Should burn batch multiple tokens successfully", async function () {
    //         await expect(membershipERC1155.connect(deployer).burnBatchMultiple([user.address, user.address]))
    //             .to.emit(membershipERC1155, "TransferSingle");
    //         expect(await membershipERC1155.balanceOf(user.address, 1)).to.equal(0);
    //     });

    //     it("Should fail to burn tokens if not called by OWP_FACTORY_ROLE", async function () {
    //         await expect(membershipERC1155.connect(nonAdmin).burnBatch(user.address))
    //             .to.be.revertedWith("AccessControl: account 0x90f79bf6eb2c4f870365e785982e1f101e93b906 is missing role 0x8b78a73274a0ca608391d82d111f52b8320c4327ef3d42a14e24e41e7622dfd6");
    //     });

    //     it("Should fail to burn tokens if not called by OWP_FACTORY_ROLE", async function () {
    //         await expect(membershipERC1155.connect(nonAdmin).burnBatchMultiple([user.address]))
    //             .to.be.revertedWith("AccessControl: account 0x90f79bf6eb2c4f870365e785982e1f101e93b906 is missing role 0x8b78a73274a0ca608391d82d111f52b8320c4327ef3d42a14e24e41e7622dfd6");
    //     });
    // });

    // describe("Profit Sharing", function () {

    //     it("Should distribute and claim profits correctly", async function () {
    //         await testERC20.mint(nonAdmin.address, ethers.utils.parseEther("20"));
    //         await testERC20.connect(nonAdmin).approve(membershipERC1155.address, ethers.utils.parseEther("20"));

    //         const initialContractBalance = await testERC20.balanceOf(membershipERC1155.address);
    //         await membershipERC1155.connect(nonAdmin).sendProfit(testERC20.address, ethers.utils.parseEther("2"));
    //         const userProfit = await membershipERC1155.profitOf(user.address, testERC20.address);
    //         expect(userProfit).to.equal(0);

    //         const contractBalance = await testERC20.balanceOf(membershipERC1155.address);
            
    //         expect(contractBalance).to.equal(initialContractBalance.sub(userProfit));
                 
    //     });

    //     it("Should distribute and claim profits correctly", async function () {
    //         await membershipERC1155.connect(deployer).mint(user.address, 1, 100);
    //         await membershipERC1155.connect(deployer).mint(anotherUser.address, 1, 100);
    //         await testERC20.mint(nonAdmin.address, ethers.utils.parseEther("20"));
    //         await testERC20.connect(nonAdmin).approve(membershipERC1155.address, ethers.utils.parseEther("20"));
    //         await membershipERC1155.connect(nonAdmin).sendProfit(testERC20.address, ethers.utils.parseEther("2"));
    //         const userProfit = await membershipERC1155.profitOf(user.address, testERC20.address);
    //         expect(userProfit).to.be.above(0);

    //         const beforeBalance = await testERC20.balanceOf(user.address);
    //         const initialContractBalance = await testERC20.balanceOf(membershipERC1155.address);

    //         // Perform the action
    //         await membershipERC1155.connect(user).claimProfit(testERC20.address);
            
    //         const afterBalance = await testERC20.balanceOf(user.address);
    //         const contractBalance = await testERC20.balanceOf(membershipERC1155.address);
            
    //         // Check the balances
    //         expect(afterBalance.sub(beforeBalance)).to.equal(userProfit);
    //         expect(contractBalance).to.equal(initialContractBalance.sub(userProfit));
                 
    //     });

    //     it("Should fail to claim profits if no profits available", async function () {
    //         await membershipERC1155.connect(deployer).mint(user.address, 1, 100);
    //         await membershipERC1155.connect(deployer).mint(anotherUser.address, 1, 100);
    //         await expect(membershipERC1155.connect(user).claimProfit(ethers.constants.AddressZero))
    //             .to.be.revertedWith("No profit available");
    //     });
    // });

    // describe("Setting URI", function () {
    //     it("Should set new URI", async function () {
    //         const newURI = "https://newexample.com/";
    //         await membershipERC1155.connect(deployer).setURI(newURI);
    //         expect(await membershipERC1155.uri(1)).to.equal(newURI+membershipERC1155.address.toLowerCase()+'/1');
    //     });

    //     it("Should fail to set URI if not admin", async function () {
    //         const newURI = "https://newexample.com/{id}.json";
    //         await expect(membershipERC1155.connect(nonAdmin).setURI(newURI))
    //             .to.be.revertedWith("AccessControl: account 0x90f79bf6eb2c4f870365e785982e1f101e93b906 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
    //     });
    // });
    // const { expect } = require("chai");

    // describe("ERC1155 and AccessControl Interface Support", function () {
    //     it("should return true for supported interfaces", async function () {
    //         const supportedInterfaces = [
    //             '0xd9b67a26', // ERC1155 interface ID
    //             '0x7965db0b', // AccessControl interface ID
    //             '0x01ffc9a7', // ERC165 interface ID
    //             // Add other supported interface IDs here
    //         ];
    
    //         for (const interfaceId of supportedInterfaces) {
    //             expect(await membershipERC1155.supportsInterface(interfaceId)).to.be.true;
    //         }
    //     });

    //     it("should return false for unsupported interfaces", async function () {
    //         const unsupportedInterfaceId = '0x12345678'; // An example of unsupported interface ID
    
    //         expect(await membershipERC1155.supportsInterface(unsupportedInterfaceId)).to.be.false;
    //     });
    // });

    // describe("Call External Contract", function () {
    //     it("Should perform an external call", async function () {
    
    //       const data = testERC20.interface.encodeFunctionData("mint", [user.address, ethers.utils.parseEther('1')]);
    //       await expect(membershipERC1155.callExternalContract(testERC20.address, data)).to.not.be.reverted;
    //     });
          
    //     it("Should fail if external call fails", async function () { 
    
    //         // Create calldata for a non-existent function
    //         const data = testERC20.interface.encodeFunctionData("mint", [ethers.constants.AddressZero, 1]);
    //         await expect(membershipERC1155.callExternalContract(testERC20.address, data)).to.be.revertedWith("External call failed");
    //     });
    //     });
          
    });
