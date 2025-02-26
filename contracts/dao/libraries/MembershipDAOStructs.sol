// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

uint64 constant TIER_MAX = 7;

//q- Ok it looks like there are certain DAO Types, So there must be checks to make sure a user can only access the correct DAO type
enum DAOType { 
    PUBLIC,
    PRIVATE,
    SPONSORED
}

//q- Configurations of a DAO, a dao can have multiple tiers?
struct DAOConfig {
    string ensname;
    DAOType daoType;
    TierConfig[] tiers;
    address currency;
    uint256 maxMembers;
    uint256 noOfTiers;
    //joined members check
}

struct DAOInputConfig {
    string ensname;
    DAOType daoType;
    address currency;
    uint256 maxMembers;
    uint256 noOfTiers;
}

//q- What does each tier represent.
struct TierConfig {
    uint256 amount; //max number of minted tokens
    uint256 price;
    uint256 power;
    uint256 minted;
}
