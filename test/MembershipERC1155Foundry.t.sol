// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {MembershipERC1155} from "../contracts/dao/tokens/MembershipERC1155.sol";
import {OWPERC20} from "../contracts/shared/testERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract MembershipERC1155Test is Test {
    MembershipERC1155 public membership;
    OWPERC20 public testERC20;

    // Use different addresses for testing.
    address deployer = address(1);
    address user = address(2);
    address anotherUser = address(3);
    address nonAdmin = address(4);

    // A sample token URI
    string tokenURI = "https://example.com/{id}.json";

    function setUp() public {
        // Deploy contracts as the deployer.
        vm.startPrank(deployer);

        // Deploy the ERC20 (which is used as the profit currency).
        testERC20 = new OWPERC20("OWP", "OWP");

        // Deploy the ERC1155 membership contract.
        membership = new MembershipERC1155();
        // Call initialize to set parameters.
        membership.initialize(
            "TestToken",      // name
            "TST",            // symbol
            tokenURI,         // base URI
            deployer,         // creator (and DAO creator)
            address(testERC20) // currency address
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              Deployment
    //////////////////////////////////////////////////////////////*/

    function testDeployment() public {
        // Check that deployer has the DEFAULT_ADMIN_ROLE (which is 0x00).
        bytes32 DEFAULT_ADMIN_ROLE = 0x00;
        bool hasAdmin = membership.hasRole(DEFAULT_ADMIN_ROLE, deployer);
        assertTrue(hasAdmin, "Deployer should have admin role");

        // Check that creator was set to deployer.
        assertEq(membership.creator(), deployer, "Creator should be deployer");

        // Check token name and symbol.
        assertEq(membership.name(), "TestToken", "Name should be TestToken");
        assertEq(membership.symbol(), "TST", "Symbol should be TST");
    }

    /*//////////////////////////////////////////////////////////////
                             Token Minting
    //////////////////////////////////////////////////////////////*/

    function testMintingSuccess() public {
        // Caller with OWP_FACTORY_ROLE (granted during initialize to deployer) mints tokens.
        vm.prank(deployer);
        membership.mint(user, 1, 100);

        uint256 bal = membership.balanceOf(user, 1);
        assertEq(bal, 100, "User should have 100 tokens of id 1");
    }

    function testMintingFailureNonAdmin() public {
        // nonAdmin does not have the OWP_FACTORY_ROLE so this call should revert.
        vm.prank(nonAdmin);
        vm.expectRevert(); // (we simply expect a revert)
        membership.mint(user, 1, 100);
    }

    /*//////////////////////////////////////////////////////////////
                              Token Burning
    //////////////////////////////////////////////////////////////*/

    function testBurningSuccess() public {
        // First mint tokens to the user.
        vm.prank(deployer);
        membership.mint(user, 1, 100);
        // Then burn 50 tokens.
        vm.prank(deployer);
        membership.burn(user, 1, 50);

        uint256 bal = membership.balanceOf(user, 1);
        assertEq(bal, 50, "User should have 50 tokens left");
    }

    function testBurningFailureNonAdmin() public {
        vm.prank(deployer);
        membership.mint(user, 1, 100);
        vm.prank(nonAdmin);
        vm.expectRevert();
        membership.burn(user, 1, 50);
    }

    function testBurnBatchSuccess() public {
        // Mint tokens for a single token ID (e.g. id 1) to the user.
        vm.prank(deployer);
        membership.mint(user, 1, 100);
        assertEq(membership.balanceOf(user, 1), 100, "Pre-burn: user should have 100 tokens");

        // Calling burnBatch will loop over token IDs 0..6 and burn any balance.
        vm.prank(deployer);
        membership.burnBatch(user);

        // The minted token (id 1) should now be burned.
        assertEq(membership.balanceOf(user, 1), 0, "After burnBatch: user should have 0 tokens");
    }

    function testBurnBatchMultipleSuccess() public {
        // Mint tokens for user.
        vm.prank(deployer);
        membership.mint(user, 1, 100);

        // Prepare an array of addresses (e.g. user twice).
        address[] memory addrs = new address[](2);
        addrs[0] = user;
        addrs[1] = user;

        vm.prank(deployer);
        membership.burnBatchMultiple(addrs);

        // Check that tokens are burned.
        assertEq(membership.balanceOf(user, 1), 0, "After burnBatchMultiple: user should have 0 tokens");
    }

    function testBurnBatchFailureNonAdmin() public {
        vm.prank(deployer);
        membership.mint(user, 1, 100);
        vm.prank(nonAdmin);
        vm.expectRevert();
        membership.burnBatch(user);
    }

    function testBurnBatchMultipleFailureNonAdmin() public {
        vm.prank(deployer);
        membership.mint(user, 1, 100);
        address[] memory addrs = new address[](1);
        addrs[0] = user;
        vm.prank(nonAdmin);
        vm.expectRevert();
        membership.burnBatchMultiple(addrs);
    }

    /*//////////////////////////////////////////////////////////////
                            Profit Sharing
    //////////////////////////////////////////////////////////////*/

    function testProfitSharingNoTokens() public {
        // Mint some ERC20 tokens to nonAdmin and approve the membership contract.
        vm.prank(nonAdmin);
        testERC20.mint(nonAdmin, 20 ether);
        vm.prank(nonAdmin);
        testERC20.approve(address(membership), 20 ether);

        uint256 initialContractBalance = testERC20.balanceOf(address(membership));

        // Since no membership tokens have been minted, totalSupply is 0.
        // sendProfit will redirect funds to creator so no profit is available for user.
        vm.prank(nonAdmin);
        membership.sendProfit(2 ether);

        uint256 userProfit = membership.profitOf(user);
        assertEq(userProfit, 0, "User profit should be zero if no tokens held");

        // When totalSupply is zero, funds are sent to creator so the contract balance remains unchanged.
        uint256 contractBalance = testERC20.balanceOf(address(membership));
        assertEq(contractBalance, initialContractBalance, "Contract balance should remain unchanged");
    }

    function testProfitSharingDistributionAndClaim() public {
        // Mint membership tokens for both user and anotherUser.
        vm.prank(deployer);
        membership.mint(user, 1, 100);
        vm.prank(deployer);
        membership.mint(anotherUser, 1, 100);

        // Mint ERC20 tokens to nonAdmin and approve the membership contract.
        vm.prank(nonAdmin);
        testERC20.mint(nonAdmin, 20 ether);
        vm.prank(nonAdmin);
        testERC20.approve(address(membership), 20 ether);

        // Send profit.
        vm.prank(nonAdmin);
        membership.sendProfit(2 ether);

        uint256 userProfit = membership.profitOf(user);
        assertGt(userProfit, 0, "User profit should be greater than zero");

        uint256 beforeBalance = testERC20.balanceOf(user);
        uint256 initialContractBalance = testERC20.balanceOf(address(membership));

        // User claims profit.
        vm.prank(user);
        membership.claimProfit();

        uint256 afterBalance = testERC20.balanceOf(user);
        uint256 contractBalance = testERC20.balanceOf(address(membership));

        assertEq(afterBalance - beforeBalance, userProfit, "User balance should increase by the claimed profit");
        assertEq(initialContractBalance - contractBalance, userProfit, "Contract balance should decrease by the claimed profit");
    }

    function testClaimProfitFailureWhenNone() public {
        // Mint tokens so that a profit could be computed but without sending any profit.
        vm.prank(deployer);
        membership.mint(user, 1, 100);
        vm.prank(deployer);
        membership.mint(anotherUser, 1, 100);
        vm.prank(user);
        vm.expectRevert("No profit available");
        membership.claimProfit();
    }

    /*//////////////////////////////////////////////////////////////
                             Setting URI
    //////////////////////////////////////////////////////////////*/

    function testSetURIByAdmin() public {
        string memory newURI = "https://newexample.com/";
        vm.prank(deployer);
        membership.setURI(newURI);

        // Expected URI is the new base URI concatenated with the membership contract address (in hex) and the token ID.
        string memory expected = string(abi.encodePacked(
            newURI,
            Strings.toHexString(uint160(address(membership)), 20),
            "/",
            "1"
        ));
        string memory actual = membership.uri(1);
        assertEq(actual, expected, "URI should be updated correctly");
    }

    function testSetURIFailureNonAdmin() public {
        string memory newURI = "https://newexample.com/{id}.json";
        vm.prank(nonAdmin);
        vm.expectRevert();
        membership.setURI(newURI);
    }

    /*//////////////////////////////////////////////////////////////
                     ERC1155 and AccessControl Support
    //////////////////////////////////////////////////////////////*/

    function testSupportsInterfaces() public {
        // Supported interface IDs.
        bytes4[3] memory supported = [
            bytes4(0xd9b67a26), // ERC1155 interface ID
            bytes4(0x7965db0b), // AccessControl interface ID
            bytes4(0x01ffc9a7)  // ERC165 interface ID
        ];

        for (uint256 i = 0; i < supported.length; i++) {
            bool isSupported = membership.supportsInterface(supported[i]);
            assertTrue(isSupported, "Interface should be supported");
        }

        // An unsupported interface.
        bool unsupported = membership.supportsInterface(0x12345678);
        assertFalse(unsupported, "Interface should not be supported");
    }

    /*//////////////////////////////////////////////////////////////
                         Call External Contract
    //////////////////////////////////////////////////////////////*/

    function testCallExternalContractSuccess() public {
        // Prepare call data to invoke testERC20.mint(user, 1 ether).
        bytes memory data = abi.encodeWithSignature("mint(address,uint256)", user, 1 ether);

        vm.prank(deployer);
        bytes memory result = membership.callExternalContract(address(testERC20), data);

        // Check that the external call succeeded by verifying the ERC20 balance.
        uint256 bal = testERC20.balanceOf(user);
        assertEq(bal, 1 ether, "User should receive 1 ether worth of tokens from external call");
    }

    function testCallExternalContractFailure() public {
        // Prepare invalid call data (mint to address(0) will revert in ERC20).
        bytes memory data = abi.encodeWithSignature("mint(address,uint256)", address(0), 1);
        vm.prank(deployer);
        vm.expectRevert(bytes("External call failed"));
        membership.callExternalContract(address(testERC20), data);
    }
}
