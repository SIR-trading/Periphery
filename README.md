# SIR Periphery

This repository generated with [Foundry](https://book.getfoundry.sh/) contains the auxiliary contract files to the SIR protocol.

### Contracts

The `Assistant` contract serves as a helper for the SIR protocol, providing essential functions that facilitate interactions with various components of the system. Key functionalities include:

-   **Quoting Token Transactions**: Functions like `quoteMint` allow users to simulate token minting by depositing collateral.
-   **Vault Status**: Function for querying the status of a vault (e.g. whether the vault exists, can be initialized, etc).

The `TreasuryV1` contract is the initial implementation of the Treasury for the SIR protocol. It is an upgradeable contract that allows the owner to perform administrative actions on behalf of the treasury, like minting SIR.

<!-- ## Ethereum Mainnet Addresses

| Contract Name  | Ethereum Mainnet Address                                                                                              |
| -------------- | --------------------------------------------------------------------------------------------------------------------- |
| TreasuryV1.sol | [0x686748764c5C7Aa06FEc784E60D14b650bF79129](https://etherscan.io/address/0x686748764c5C7Aa06FEc784E60D14b650bF79129) |
| Assistant.sol  | [0x8e141368a00244A17724F76E682518DD9286cCb3](https://etherscan.io/address/0x8e141368a00244A17724F76E682518DD9286cCb3) | -->
