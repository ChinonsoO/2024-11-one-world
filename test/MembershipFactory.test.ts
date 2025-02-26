const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MembershipFactory", function () {
  let MembershipFactory, membershipFactory:any, MembershipERC1155:any, membershipERC1155:any, testERC20:any;
  let currencyManager:any, CurrencyManager, owner:any, addr1:any, addr2, addrs;
  let DAOType:any, DAOConfig:any, TierConfig:any;
  
  beforeEach(async function () {
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
    
    CurrencyManager = await ethers.getContractFactory("CurrencyManager");
    currencyManager = await CurrencyManager.deploy({gasLimit: 9000000});
    await currencyManager.deployed();

    MembershipERC1155 = await ethers.getContractFactory('MembershipERC1155');
    const membershipImplementation = await MembershipERC1155.deploy({gasLimit: 9000000});
    await membershipImplementation.deployed();

    MembershipFactory = await ethers.getContractFactory("MembershipFactory");
    membershipFactory = await MembershipFactory.deploy(currencyManager.address, owner.address, "https://baseuri.com/", membershipImplementation.address);
    await membershipFactory.deployed();

    const ERC20 = await ethers.getContractFactory("OWPERC20");
    testERC20 = await ERC20.deploy('OWP', 'OWP', {gasLimit: 9000000});
    await testERC20.deployed();
    // await currencyManager.addCurrency(testERC20.address);
    DAOType = { GENERAL: 0, PRIVATE: 1, SPONSORED: 2 };
    DAOConfig = { ensname: "testdao.eth", daoType: DAOType.GENERAL, currency: testERC20.address, maxMembers: 100, noOfTiers: 3 };
    TierConfig = [{ price: 300, amount: 10, minted: 0, power: 12 }, { price: 200, amount: 10, minted: 0, power:6 }, { price: 100, amount: 10, minted: 0, power: 3 }];
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await membershipFactory.hasRole(await membershipFactory.DEFAULT_ADMIN_ROLE(), owner.address)).to.be.true;
    });

    it("Should set the correct baseURI", async function () {
      expect(await membershipFactory.baseURI()).to.equal("https://baseuri.com/");
    });

    it("Should set the correct currencyManager", async function () {
      expect(await membershipFactory.currencyManager()).to.equal(currencyManager.address);
    });
  });

  describe("Create New DAO Membership", function () {
    it("Should create a new DAO Membership", async function () {
      await currencyManager.addCurrency(testERC20.address);  // Assume addCurrency function exists in CurrencyManager

      const tx = await membershipFactory.createNewDAOMembership(DAOConfig, TierConfig);
      const receipt = await tx.wait();
      const event = receipt.events.find((event:any) => event.event === "MembershipDAONFTCreated");
      const ensName = event.args[2][0];
      const nftAddress = event.args[1];
      const ensToAddress = await membershipFactory.getENSAddress("testdao.eth")
      expect(ensName).to.equal("testdao.eth");
      expect(ensToAddress).to.equal(nftAddress);
    });

    it("Should create DAO membership if tier amounts sum to maxMembers or less", async function () {
        const daoConfig = {
            ensname: "testdao.eth",
            currency: testERC20.address,
            maxMembers: 100,
            noOfTiers: 2,
            daoType: 0 // Assuming 0 represents a specific DAO type for testing
        };

        const tierConfigs = [
            { amount: 50, minted: 0 },
            { amount: 50, minted: 0 },
        ];

        await expect(membershipERC1155.createNewDAOMembership(daoConfig, tierConfigs))
            .to.emit(membershipERC1155, "MembershipDAONFTCreated");
    });

    it("Should fail to create DAO membership if tier amounts exceed maxMembers", async function () {
        const daoConfig = {
            ensname: "exceeddao.eth",
            currency: testERC20.address,
            maxMembers: 100,
            noOfTiers: 2,
            daoType: 0 // Assuming 0 represents a specific DAO type for testing
        };

        const tierConfigs = [
            { amount: 80, minted: 0 },
            { amount: 30, minted: 0 }, // This sum (110) exceeds maxMembers (100)
        ];

        await expect(membershipERC1155.createNewDAOMembership(daoConfig, tierConfigs))
            .to.be.revertedWith("Sum of tier amounts exceeds maxMembers.");
    });

    it("Should fail if currency is not whitelisted", async function () {
      await expect(membershipFactory.createNewDAOMembership(DAOConfig, TierConfig)).to.be.revertedWith("Currency not accepted.");
    });

    it("Should fail if dao already exists", async function () {
      await currencyManager.addCurrency(testERC20.address);
      const tx = await membershipFactory.createNewDAOMembership(DAOConfig, TierConfig);
      const receipt = await tx.wait();
      await expect(membershipFactory.createNewDAOMembership(DAOConfig, TierConfig)).to.be.revertedWith("DAO already exist.");
    });

    it("Should fail if tier count is invalid", async function () {
      DAOConfig.noOfTiers = 0;
      TierConfig = []
      await currencyManager.addCurrency(testERC20.address);
      await expect(membershipFactory.createNewDAOMembership(DAOConfig, TierConfig)).to.be.revertedWith("Invalid tier count.");
    });

    it("Should fail if tier count is invalid", async function () {
      DAOConfig.noOfTiers = 0;
      await currencyManager.addCurrency(testERC20.address);
      await expect(membershipFactory.createNewDAOMembership(DAOConfig, TierConfig)).to.be.revertedWith("Invalid tier input.");
    });
  });

  describe("Join DAO", function () {
    beforeEach(async function () {
      await currencyManager.addCurrency(testERC20.address);  // Assume addCurrency function exists in CurrencyManager
      await membershipFactory.createNewDAOMembership(DAOConfig, TierConfig);
      const ensAddress = await membershipFactory.getENSAddress("testdao.eth");
      membershipERC1155 = await MembershipERC1155.attach(ensAddress);
    });

    it("Should allow user to join DAO", async function () {
      const tierIndex = 0;
      await testERC20.mint(addr1.address, ethers.utils.parseEther("200"));
      await testERC20.connect(addr1).approve(membershipFactory.address, TierConfig[tierIndex].price);  // Assume approve function exists in CurrencyManager
      await expect(membershipFactory.connect(addr1).joinDAO(membershipERC1155.address, tierIndex)).to.emit(membershipFactory, "UserJoinedDAO");
    });

    it("Should fail if tier index is invalid", async function () {
      await expect(membershipFactory.joinDAO(membershipERC1155.address, 5)).to.be.revertedWith("Invalid tier.");
    });

    it("Should fail if tier is full", async function () {
      const tierIndex = 0;
      TierConfig[tierIndex].amount = 1;
      DAOConfig.ensname = 'tester.eth'
      console.log({TierConfig})
      const tx = await membershipFactory.createNewDAOMembership(DAOConfig, TierConfig);
      const receipt = await tx.wait();
      
      const event = receipt.events.find((event:any) => event.event === "MembershipDAONFTCreated");
      const ensName = event.args[2][0];
      const nftAddress = event.args[1];
      await testERC20.mint(addr1.address, ethers.utils.parseEther("2000"));
      
      await testERC20.connect(addr1).approve(membershipFactory.address, ethers.utils.parseEther("2000"));  // Assume approve function exists in CurrencyManager
      await membershipFactory.connect(addr1).joinDAO(nftAddress, tierIndex);
      const daosD = await membershipFactory.daos(nftAddress);
      const tiersdata = await membershipFactory.tiers(nftAddress);
      console.log({daosD, tiersdata})
      await expect(membershipFactory.connect(addr1).joinDAO(nftAddress, tierIndex)).to.be.revertedWith("Tier full.");
    });
  });

  describe("Upgrade Tier", function () {
    beforeEach(async function () {
      DAOConfig.daoType = DAOType.SPONSORED;
      DAOConfig.noOfTiers = 7;
      const TierConfigSponsored = [{ price: 6400, amount: 640, minted: 0, power: 64 }, 
                                    { price: 3200, amount: 320, minted: 0, power:32 }, 
                                    { price: 1600, amount: 160, minted: 0, power:16 }, 
                                    { price: 800, amount: 80, minted: 0, power:8 }, 
                                    { price: 400, amount: 40, minted: 0, power:4 }, 
                                    { price: 200, amount: 20, minted: 0, power:2 }, 
                                    { price: 100, amount: 10, minted: 0, power: 1 }];
      await currencyManager.addCurrency(testERC20.address);  // Assume addCurrency function exists in CurrencyManager
      await membershipFactory.createNewDAOMembership(DAOConfig, TierConfigSponsored);
      const ensAddress = await membershipFactory.getENSAddress("testdao.eth");
      membershipERC1155 = await MembershipERC1155.attach(ensAddress);
    });

    it("Should allow user to upgrade tier", async function () {
      const fromTierIndex = 1;
      await testERC20.mint(addr1.address, ethers.utils.parseEther("1000000"));
      await testERC20.connect(addr1).approve(membershipFactory.address, ethers.utils.parseEther("1000000"));
      await membershipFactory.connect(addr1).joinDAO(membershipERC1155.address, fromTierIndex);
      await membershipFactory.connect(addr1).joinDAO(membershipERC1155.address, fromTierIndex);
      await expect(membershipFactory.connect(addr1).upgradeTier(membershipERC1155.address, fromTierIndex)).to.emit(membershipFactory, "UserJoinedDAO");
    });

    it("Should fail if not a sponsored DAO", async function () {
      DAOConfig = { ensname: "testdao.eth", daoType: DAOType.GENERAL, currency: testERC20.address, maxMembers: 100, noOfTiers: 3 };
      TierConfig = [{ price: 300, amount: 10, minted: 0, power: 12 }, { price: 200, amount: 10, minted: 0, power:6 }, { price: 100, amount: 10, minted: 0, power: 3 }];
      
      DAOConfig.daoType = DAOType.GENERAL;
      DAOConfig.ensname = "testdao2.eth";
      // await currencyManager.addCurrency(testERC20.address);  // Assume addCurrency function exists in CurrencyManager
      await membershipFactory.createNewDAOMembership(DAOConfig, TierConfig);
      const ensAddress = await membershipFactory.getENSAddress("testdao2.eth");
      membershipERC1155 = await MembershipERC1155.attach(ensAddress);
      await expect(membershipFactory.connect(addr1).upgradeTier(membershipERC1155.address, 0)).to.be.revertedWith("Upgrade not allowed.");
    });

    it("Should fail if no higher tier available", async function () {
      const fromTierIndex = 50;

      await testERC20.connect(addr1).approve(membershipFactory.address, TierConfig[0].price);  // Assume approve function exists in CurrencyManager
      await expect(membershipFactory.connect(addr1).upgradeTier(membershipERC1155.address, fromTierIndex)).to.be.revertedWith("No higher tier available.");
    });
  });

  describe("Update DAO Membership", function () {
    it("Should update DAO Membership", async function () {
      await currencyManager.addCurrency(testERC20.address);  // Assume addCurrency function exists in CurrencyManager
      await membershipFactory.createNewDAOMembership(DAOConfig, TierConfig);
      const newTierConfig = [{ price: 150, amount: 20, minted: 0, power:4 }];
      await expect(membershipFactory.updateDAOMembership("testdao.eth", newTierConfig)).to.not.be.reverted;
    });

    it("Should fail if DAO does not exist", async function () {
      await expect(membershipFactory.updateDAOMembership("nonexistentdao.eth", TierConfig)).to.be.revertedWith("DAO does not exist.");
    });

    it("Should fail if invalid caller", async function () {
      await expect(membershipFactory.connect(addr1).updateDAOMembership("nonexistentdao.eth", TierConfig)).to.be.revertedWith("AccessControl: account 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 is missing role 0x3124d52df17d64a7d650cea4d44356c1b56f1552895b7db0931fbeaabb38822a");
    });
  });

  describe("Set Currency Manager", function () {
    it("Should set new currency manager", async function () {
      const newCurrencyManager = ethers.Wallet.createRandom().address;
      await expect(membershipFactory.setCurrencyManager(newCurrencyManager)).to.not.be.reverted;
      expect(await membershipFactory.currencyManager()).to.equal(newCurrencyManager);
    });

    it("Should fail if address is invalid", async function () {
      await expect(membershipFactory.setCurrencyManager(ethers.constants.AddressZero)).to.be.revertedWith("Invalid address");
    });

    it("Should fail if caller is invalid", async function () {
      await expect(membershipFactory.connect(addr1).setCurrencyManager(testERC20.address)).to.be.revertedWith("AccessControl: account 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
    });
  });

  describe("Set new Membership address", function () {
    it("Should set new membership address", async function () {
      const newMembershipAddress = ethers.Wallet.createRandom().address;
      await expect(membershipFactory.updateMembershipImplementation(newMembershipAddress)).to.not.be.reverted;
      expect(await membershipFactory.membershipImplementation()).to.equal(newMembershipAddress);
    });

    it("Should fail if address is invalid", async function () {
      await expect(membershipFactory.updateMembershipImplementation(ethers.constants.AddressZero)).to.be.revertedWith("Invalid address");
    });

    it("Should fail if caller is invalid", async function () {
      await expect(membershipFactory.connect(addr1).updateMembershipImplementation(testERC20.address)).to.be.revertedWith("AccessControl: account 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
    });
  });

  describe("Set BaseURI", function () {
    it("Should set new currency manager", async function () {
      const newBaseURI = 'newBaseURI/';
      await expect(membershipFactory.setBaseURI(newBaseURI)).to.not.be.reverted;
      expect(await membershipFactory.baseURI()).to.equal(newBaseURI);
    });

    it("Should fail if caller is invalid", async function () {
      await expect(membershipFactory.connect(addr1).setBaseURI('newBaseURI1/')).to.be.revertedWith("AccessControl: account 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
    });
  });

  describe("Call External Contract", function () {
    it("Should perform an external call", async function () {

      const data = testERC20.interface.encodeFunctionData("mint", [addr1.address, ethers.utils.parseEther('1')]);
      await expect(membershipFactory.callExternalContract(testERC20.address, data)).to.not.be.reverted;
    });
      
    it("Should fail an unauthorized external call", async function () {

      const data = testERC20.interface.encodeFunctionData("mint", [addr1.address, ethers.utils.parseEther('1')]);
      await expect(membershipFactory.connect(addr1).callExternalContract(testERC20.address, data)).to.be.revertedWith("AccessControl: account 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 is missing role 0x3124d52df17d64a7d650cea4d44356c1b56f1552895b7db0931fbeaabb38822a");
    });

    it("Should fail if external call fails", async function () { 

        // Create calldata for a non-existent function
        const data = testERC20.interface.encodeFunctionData("mint", [ethers.constants.AddressZero, 1]);
        await expect(membershipFactory.callExternalContract(testERC20.address, data)).to.be.revertedWith("External call failed");
    });
    });
      
});
