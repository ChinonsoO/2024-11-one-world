// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Test, console } from "forge-std/Test.sol";

// Import your contracts and structs. Adjust paths as necessary.
import { DAOConfig, DAOInputConfig, TierConfig, DAOType } from "../contracts/dao/libraries/MembershipDAOStructs.sol";
import { CurrencyManager } from "../contracts/dao/CurrencyManager.sol";
import { MembershipFactory } from "../contracts/dao/MembershipFactory.sol";
import { MembershipERC1155 } from "../contracts/dao/tokens/MembershipERC1155.sol";
import { OWPERC20 } from "../contracts/shared/testERC20.sol";

contract MembershipFactoryTest is Test {
    CurrencyManager currencyManager;
    MembershipFactory membershipFactory;
    MembershipERC1155 membershipERC1155;
    OWPERC20 testERC20;

    address owner = address(1);
    address addr1 = address(2);
    address addr2 = address(3);

    // We'll still use a DAOConfig for our local storage settings, but when calling createNewDAOMembership we convert it.
    DAOConfig daoConfig;
    TierConfig[] tierConfigs;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy CurrencyManager.
        currencyManager = new CurrencyManager();

        // Deploy a MembershipERC1155 implementation.
        MembershipERC1155 membershipImpl = new MembershipERC1155();

        // Deploy MembershipFactory.
        // (Assuming your constructor takes (address currencyManager, address owner, string baseURI, address membershipImplementation))
        membershipFactory = new MembershipFactory(
            address(currencyManager),
            owner,
            "https://baseuri.com/",
            address(membershipImpl)
        );

        // Deploy the ERC20 used as currency.
        testERC20 = new OWPERC20("OWP", "OWP");

        // Set a default DAO config.
        // Note: The MembershipFactory expects a DAOInputConfig, so we’ll convert this later.

        daoConfig.ensname = "testdao.eth";
        daoConfig.daoType = DAOType.PUBLIC;
        daoConfig.currency = address(testERC20);
        daoConfig.maxMembers = 100;
        daoConfig.noOfTiers = 3;
        delete daoConfig.tiers; // ensures the tiers array is empty

        // Set up a default TierConfig array.
        delete tierConfigs;
        tierConfigs.push(TierConfig({ price: 300, amount: 10, minted: 0, power: 12 }));
        tierConfigs.push(TierConfig({ price: 200, amount: 10, minted: 0, power: 6 }));
        tierConfigs.push(TierConfig({ price: 100, amount: 10, minted: 0, power: 3 }));

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              Deployment Tests
    //////////////////////////////////////////////////////////////*/

    function testDeployment() public {
        // Check that owner has the default admin role.
        bytes32 defaultAdmin = membershipFactory.DEFAULT_ADMIN_ROLE();
        bool hasAdmin = membershipFactory.hasRole(defaultAdmin, owner);
        assertTrue(hasAdmin, "Owner should have admin role");

        // Check the baseURI and currencyManager.
        assertEq(membershipFactory.baseURI(), "https://baseuri.com/", "BaseURI not set correctly");
        assertEq(address(membershipFactory.currencyManager()), address(currencyManager), "CurrencyManager not set correctly");
    }

    /*//////////////////////////////////////////////////////////////
                       Create New DAO Membership
    //////////////////////////////////////////////////////////////*/

    function testCreateNewDAOMembership() public {
        vm.prank(owner);
        currencyManager.addCurrency(address(testERC20));

        // Convert daoConfig to DAOInputConfig
        DAOInputConfig memory inputConfig = DAOInputConfig({
            ensname: daoConfig.ensname,
            daoType: daoConfig.daoType,
            currency: daoConfig.currency,
            maxMembers: daoConfig.maxMembers,
            noOfTiers: daoConfig.noOfTiers
        });

        console.log("InputConfig: ", inputConfig.ensname);
        vm.prank(owner);
        membershipFactory.createNewDAOMembership(inputConfig, tierConfigs);

        address nftAddress = membershipFactory.getENSAddress("testdao.eth");
        assertTrue(nftAddress != address(0), "NFT address should not be zero");
    }

    function testCreateDAOMembership_TierAmountWithinMaxMembers() public {
        DAOConfig memory localDAO = DAOConfig({
            ensname: "testdao.eth",
            daoType: DAOType.PUBLIC,
            tiers: new TierConfig[](0),
            currency: address(testERC20),
            maxMembers: 100,
            noOfTiers: 2
        });
        TierConfig[] memory localTiers = new TierConfig[](2);
        localTiers[0] = TierConfig({ amount: 50, minted: 0, price: 300, power: 12 });
        localTiers[1] = TierConfig({ amount: 50, minted: 0, price: 200, power: 6 });

        // Convert localDAO to DAOInputConfig
        DAOInputConfig memory inputConfig = DAOInputConfig({
            ensname: localDAO.ensname,
            daoType: localDAO.daoType,
            currency: localDAO.currency,
            maxMembers: localDAO.maxMembers,
            noOfTiers: localDAO.noOfTiers
        });

        vm.prank(owner);
        currencyManager.addCurrency(address(testERC20));
        vm.prank(owner);
        membershipFactory.createNewDAOMembership(inputConfig, localTiers);

        address nftAddress = membershipFactory.getENSAddress("testdao.eth");
        assertTrue(nftAddress != address(0), "DAO membership creation failed");
    }

    function testCreateDAOMembership_TierAmountExceedsMaxMembers() public {
        DAOConfig memory localDAO = DAOConfig({
            ensname: "exceeddao.eth",
            daoType: DAOType.PUBLIC,
            tiers: new TierConfig[](0),
            currency: address(testERC20),
            maxMembers: 100,
            noOfTiers: 2
        });
        TierConfig[] memory localTiers = new TierConfig[](2);
        localTiers[0] = TierConfig({ amount: 80, minted: 0, price: 300, power: 12 });
        localTiers[1] = TierConfig({ amount: 30, minted: 0, price: 200, power: 6 });

        DAOInputConfig memory inputConfig = DAOInputConfig({
            ensname: localDAO.ensname,
            daoType: localDAO.daoType,
            currency: localDAO.currency,
            maxMembers: localDAO.maxMembers,
            noOfTiers: localDAO.noOfTiers
        });

        vm.prank(owner);
        currencyManager.addCurrency(address(testERC20));
        vm.prank(owner);
        vm.expectRevert(bytes("Sum of tier amounts exceeds maxMembers."));
        membershipFactory.createNewDAOMembership(inputConfig, localTiers);
    }

    function testCreateDAOMembership_CurrencyNotWhitelisted() public {
        DAOInputConfig memory inputConfig = DAOInputConfig({
            ensname: daoConfig.ensname,
            daoType: daoConfig.daoType,
            currency: daoConfig.currency,
            maxMembers: daoConfig.maxMembers,
            noOfTiers: daoConfig.noOfTiers
        });
        vm.prank(owner);
        vm.expectRevert(bytes("Currency not accepted."));
        membershipFactory.createNewDAOMembership(inputConfig, tierConfigs);
    }

    function testCreateDAOMembership_DAOAlreadyExists() public {
        DAOInputConfig memory inputConfig = DAOInputConfig({
            ensname: daoConfig.ensname,
            daoType: daoConfig.daoType,
            currency: daoConfig.currency,
            maxMembers: daoConfig.maxMembers,
            noOfTiers: daoConfig.noOfTiers
        });

        vm.prank(owner);
        currencyManager.addCurrency(address(testERC20));
        vm.prank(owner);
        membershipFactory.createNewDAOMembership(inputConfig, tierConfigs);
        vm.prank(owner);
        vm.expectRevert(bytes("DAO already exist."));
        membershipFactory.createNewDAOMembership(inputConfig, tierConfigs);
    }

    function testCreateDAOMembership_InvalidTierCount() public {
    vm.prank(owner);
    currencyManager.addCurrency(address(testERC20));

    // Case A: noOfTiers is 0 and an empty tiers array is provided.
        TierConfig[] memory emptyTiers = new TierConfig[](0);
        DAOInputConfig memory inputConfigA = DAOInputConfig({
            ensname: "testdao.eth",
            daoType: DAOType.PUBLIC,
            currency: address(testERC20),
            maxMembers: 100,
            noOfTiers: 0
        });
        vm.prank(owner);
        vm.expectRevert(bytes("Invalid tier count."));
        membershipFactory.createNewDAOMembership(inputConfigA, emptyTiers);

        // Case B: noOfTiers is 0 but a non-empty tiers array is provided.
        // This should revert with "Invalid tier input." because 0 != tierConfigs.length.
        DAOInputConfig memory inputConfigB = DAOInputConfig({
            ensname: "testdao.eth",
            daoType: DAOType.PUBLIC,
            currency: address(testERC20),
            maxMembers: 100,
            noOfTiers: 0
        });
        vm.prank(owner);
        vm.expectRevert(bytes("Invalid tier input."));
        membershipFactory.createNewDAOMembership(inputConfigB, tierConfigs);
    }

    /*//////////////////////////////////////////////////////////////
                               Join DAO Tests
    //////////////////////////////////////////////////////////////*/

    /// @dev Helper to create a DAO and attach the MembershipERC1155 instance.
    function setupDAOForJoin() internal {
        DAOInputConfig memory inputConfig = DAOInputConfig({
            ensname: daoConfig.ensname,
            daoType: daoConfig.daoType,
            currency: daoConfig.currency,
            maxMembers: daoConfig.maxMembers,
            noOfTiers: daoConfig.noOfTiers
        });
        vm.prank(owner);
        currencyManager.addCurrency(address(testERC20));
        vm.prank(owner);
        membershipFactory.createNewDAOMembership(inputConfig, tierConfigs);
        address nftAddress = membershipFactory.getENSAddress("testdao.eth");
        membershipERC1155 = MembershipERC1155(nftAddress);
    }

    function testJoinDAO_Success() public {
        setupDAOForJoin();
        uint256 tierIndex = 0;

        // Mint ERC20 tokens and approve.
        vm.prank(owner);
        testERC20.mint(addr1, 200 ether);
        vm.prank(addr1);
        testERC20.approve(address(membershipFactory), tierConfigs[tierIndex].price);

        vm.prank(addr1);
        membershipFactory.joinDAO(address(membershipERC1155), tierIndex);

        uint256 balance = membershipERC1155.balanceOf(addr1, tierIndex);
        assertGt(balance, 0, "User did not join DAO");
    }

    function testJoinDAO_InvalidTier() public {
        setupDAOForJoin();
        uint256 invalidTier = 5;
        vm.prank(addr1);
        vm.expectRevert(bytes("Invalid tier."));
        membershipFactory.joinDAO(address(membershipERC1155), invalidTier);
    }

    function testJoinDAO_TierFull() public {
        // Create DAO with tier capacity 1.
        DAOConfig memory localDAO = DAOConfig({
            ensname: "tester.eth",
            daoType: DAOType.PUBLIC,
            tiers: new TierConfig[](0),
            currency: address(testERC20),
            maxMembers: 100,
            noOfTiers: 1
        });
        TierConfig[] memory localTiers = new TierConfig[](1);
        localTiers[0] = TierConfig({ amount: 1, minted: 0, price: 300, power: 12 });

        DAOInputConfig memory inputConfig = DAOInputConfig({
            ensname: localDAO.ensname,
            daoType: localDAO.daoType,
            currency: localDAO.currency,
            maxMembers: localDAO.maxMembers,
            noOfTiers: localDAO.noOfTiers
        });

        vm.prank(owner);
        currencyManager.addCurrency(address(testERC20));
        vm.prank(owner);
        membershipFactory.createNewDAOMembership(inputConfig, localTiers);
        address nftAddress = membershipFactory.getENSAddress("tester.eth");
        membershipERC1155 = MembershipERC1155(nftAddress);

        vm.prank(owner);
        testERC20.mint(addr1, 2000 ether);
        vm.prank(addr1);
        testERC20.approve(address(membershipFactory), 2000 ether);

        vm.prank(addr1);
        membershipFactory.joinDAO(nftAddress, 0);

        vm.prank(addr1);
        vm.expectRevert(bytes("Tier full."));
        membershipFactory.joinDAO(nftAddress, 0);
    }

    /*//////////////////////////////////////////////////////////////
                              Upgrade Tier Tests
    //////////////////////////////////////////////////////////////*/

    /// @dev Helper to set up a sponsored DAO with 7 tiers.
    function setupDAOForUpgrade() internal {
        daoConfig.daoType = DAOType.SPONSORED;
        daoConfig.noOfTiers = 7;
        delete tierConfigs;
        tierConfigs.push(TierConfig({ price: 6400, amount: 640, minted: 0, power: 64 }));
        tierConfigs.push(TierConfig({ price: 3200, amount: 320, minted: 0, power: 32 }));
        tierConfigs.push(TierConfig({ price: 1600, amount: 160, minted: 0, power: 16 }));
        tierConfigs.push(TierConfig({ price: 800, amount: 80, minted: 0, power: 8 }));
        tierConfigs.push(TierConfig({ price: 400, amount: 40, minted: 0, power: 4 }));
        tierConfigs.push(TierConfig({ price: 200, amount: 20, minted: 0, power: 2 }));
        tierConfigs.push(TierConfig({ price: 100, amount: 10, minted: 0, power: 1 }));

        DAOInputConfig memory inputConfig = DAOInputConfig({
            ensname: daoConfig.ensname,
            daoType: daoConfig.daoType,
            currency: daoConfig.currency,
            maxMembers: 1270,
            noOfTiers: daoConfig.noOfTiers
        });

        vm.prank(owner);
        currencyManager.addCurrency(address(testERC20));
        vm.prank(owner);
        membershipFactory.createNewDAOMembership(inputConfig, tierConfigs);
        address nftAddress = membershipFactory.getENSAddress("testdao.eth");
        membershipERC1155 = MembershipERC1155(nftAddress);
    }

    function testUpgradeTier_Success() public {
        setupDAOForUpgrade();
        uint256 fromTierIndex = 1;

        vm.prank(owner);
        testERC20.mint(addr1, 1000000 ether);
        vm.prank(addr1);
        testERC20.approve(address(membershipFactory), 1000000 ether);

        vm.prank(addr1);
        membershipFactory.joinDAO(address(membershipERC1155), fromTierIndex);
        vm.prank(addr1);
        membershipFactory.joinDAO(address(membershipERC1155), fromTierIndex);

        vm.prank(addr1);
        membershipFactory.upgradeTier(address(membershipERC1155), fromTierIndex);

        uint256 upgradedBalance = membershipERC1155.balanceOf(addr1, fromTierIndex - 1);
        assertGt(upgradedBalance, 0, "User did not upgrade tier");
    }

    function testUpgradeTier_NotSponsoredDAO() public {
        daoConfig.daoType = DAOType.PUBLIC;
        daoConfig.ensname = "testdao2.eth";
        DAOConfig memory localDAO = daoConfig;
        DAOInputConfig memory inputConfig = DAOInputConfig({
            ensname: localDAO.ensname,
            daoType: localDAO.daoType,
            currency: localDAO.currency,
            maxMembers: localDAO.maxMembers,
            noOfTiers: localDAO.noOfTiers
        });
        // Reuse the default tierConfigs.
        vm.prank(owner);
        currencyManager.addCurrency(address(testERC20));
        vm.prank(owner);
        membershipFactory.createNewDAOMembership(inputConfig, tierConfigs);
        address nftAddress = membershipFactory.getENSAddress("testdao2.eth");
        membershipERC1155 = MembershipERC1155(nftAddress);

        vm.prank(addr1);
        vm.expectRevert(bytes("Upgrade not allowed."));
        membershipFactory.upgradeTier(nftAddress, 0);
    }

    function testUpgradeTier_NoHigherTierAvailable() public {
        setupDAOForUpgrade();
        uint256 fromTierIndex = 50;
        vm.prank(addr1);
        testERC20.mint(addr1, 1000 ether);
        vm.prank(addr1);
        testERC20.approve(address(membershipFactory), 1000 ether);
        vm.prank(addr1);
        vm.expectRevert(bytes("No higher tier available."));
        membershipFactory.upgradeTier(address(membershipERC1155), fromTierIndex);
    }

    /*//////////////////////////////////////////////////////////////
                           Update DAO Membership Tests
    //////////////////////////////////////////////////////////////*/

    function testUpdateDAOMembership_Success() public {
        DAOInputConfig memory inputConfig = DAOInputConfig({
            ensname: daoConfig.ensname,
            daoType: daoConfig.daoType,
            currency: daoConfig.currency,
            maxMembers: daoConfig.maxMembers,
            noOfTiers: daoConfig.noOfTiers
        });
        vm.prank(owner);
        currencyManager.addCurrency(address(testERC20));
        vm.prank(owner);
        membershipFactory.createNewDAOMembership(inputConfig, tierConfigs);

        TierConfig[] memory newTierConfig = new TierConfig[](1);
        newTierConfig[0] = TierConfig({ price: 150, amount: 20, minted: 0, power: 4 });

        vm.prank(owner);
        membershipFactory.updateDAOMembership("testdao.eth", newTierConfig);
    }

    function testUpdateDAOMembership_DAONotExist() public {
        vm.prank(owner);
        vm.expectRevert(bytes("DAO does not exist."));
        membershipFactory.updateDAOMembership("nonexistentdao.eth", tierConfigs);
    }

    function testUpdateDAOMembership_InvalidCaller() public {
        DAOInputConfig memory inputConfig = DAOInputConfig({
            ensname: daoConfig.ensname,
            daoType: daoConfig.daoType,
            currency: daoConfig.currency,
            maxMembers: daoConfig.maxMembers,
            noOfTiers: daoConfig.noOfTiers
        });
        vm.prank(owner);
        currencyManager.addCurrency(address(testERC20));
        vm.prank(owner);
        membershipFactory.createNewDAOMembership(inputConfig, tierConfigs);

        vm.prank(addr1);
        vm.expectRevert(); // Expect AccessControl revert.
        membershipFactory.updateDAOMembership("nonexistentdao.eth", tierConfigs);
    }

    /*//////////////////////////////////////////////////////////////
                           Set Currency Manager Tests
    //////////////////////////////////////////////////////////////*/

    function testSetCurrencyManager_Success() public {
        address newCurrencyManager = address(999);
        vm.prank(owner);
        membershipFactory.setCurrencyManager(newCurrencyManager);
        assertEq(address(membershipFactory.currencyManager()), newCurrencyManager, "Currency manager not updated");
    }

    function testSetCurrencyManager_InvalidAddress() public {
        vm.prank(owner);
        vm.expectRevert(bytes("Invalid address"));
        membershipFactory.setCurrencyManager(address(0));
    }

    function testSetCurrencyManager_InvalidCaller() public {
        vm.prank(addr1);
        vm.expectRevert();
        membershipFactory.setCurrencyManager(address(testERC20));
    }

    /*//////////////////////////////////////////////////////////////
                        Set Membership Implementation Tests
    //////////////////////////////////////////////////////////////*/

    function testSetMembershipImplementation_Success() public {
        address newMembershipAddress = address(888);
        vm.prank(owner);
        membershipFactory.updateMembershipImplementation(newMembershipAddress);
        assertEq(membershipFactory.membershipImplementation(), newMembershipAddress, "Membership implementation not updated");
    }

    function testSetMembershipImplementation_InvalidAddress() public {
        vm.prank(owner);
        vm.expectRevert(bytes("Invalid address"));
        membershipFactory.updateMembershipImplementation(address(0));
    }

    function testSetMembershipImplementation_InvalidCaller() public {
        vm.prank(addr1);
        vm.expectRevert();
        membershipFactory.updateMembershipImplementation(address(testERC20));
    }

    /*//////////////////////////////////////////////////////////////
                              Set BaseURI Tests
    //////////////////////////////////////////////////////////////*/

    function testSetBaseURI_Success() public {
        string memory newBaseURI = "newBaseURI/";
        vm.prank(owner);
        membershipFactory.setBaseURI(newBaseURI);
        assertEq(membershipFactory.baseURI(), newBaseURI, "BaseURI not updated");
    }

    function testSetBaseURI_InvalidCaller() public {
        vm.prank(addr1);
        vm.expectRevert();
        membershipFactory.setBaseURI("newBaseURI1/");
    }

    /*//////////////////////////////////////////////////////////////
                           Call External Contract Tests
    //////////////////////////////////////////////////////////////*/

    function testCallExternalContract_Success() public {
        // Prepare data for testERC20.mint(addr1, 1 ether).
        bytes memory data = abi.encodeWithSignature("mint(address,uint256)", addr1, 1 ether);
        vm.prank(owner);
        membershipFactory.callExternalContract(address(testERC20), data);

        uint256 bal = testERC20.balanceOf(addr1);
        assertEq(bal, 1 ether, "External call did not mint tokens");
    }

    function testCallExternalContract_Unauthorized() public {
        bytes memory data = abi.encodeWithSignature("mint(address,uint256)", addr1, 1 ether);
        vm.prank(addr1);
        vm.expectRevert();
        membershipFactory.callExternalContract(address(testERC20), data);
    }

    function testCallExternalContract_Failure() public {
        bytes memory data = abi.encodeWithSignature("mint(address,uint256)", address(0), 1);
        vm.prank(owner);
        vm.expectRevert(bytes("External call failed"));
        membershipFactory.callExternalContract(address(testERC20), data);
    }

    function _copyTierConfigs(TierConfig[] storage source) internal view returns (TierConfig[] memory dest) {
        dest = new TierConfig[](source.length);
        for (uint256 i = 0; i < source.length; i++) {
            dest[i] = source[i];
        }
    }   
}
