# SIR Periphery

This repository generated with [Foundry](https://book.getfoundry.sh/) contains the auxiliary contract files to the SIR protocol.

### Contracts

The `Assistant` contract serves as a helper for the SIR protocol, providing essential functions that facilitate interactions with various components of the system. Key functionalities include:

-   **Quoting Token Transactions**: Functions like `quoteMint` allow users to simulate token minting by depositing collateral.
-   **Vault Status**: Function for querying the status of a vault (e.g. whether the vault exists, can be initialized, etc).

The `TreasuryV1` contract is the initial implementation of the Treasury for the SIR protocol. It is an upgradeable contract that allows the owner to perform administrative actions on behalf of the treasury, like minting SIR.

## Ethereum Mainnet Addresses

| Contract Name  | Ethereum Mainnet Address                                                                                              |
| -------------- | --------------------------------------------------------------------------------------------------------------------- |
| TreasuryV1.sol | [0x686748764c5C7Aa06FEc784E60D14b650bF79129](https://etherscan.io/address/0x686748764c5C7Aa06FEc784E60D14b650bF79129) |
| Assistant.sol  | [0x8e141368a00244A17724F76E682518DD9286cCb3](https://etherscan.io/address/0x8e141368a00244A17724F76E682518DD9286cCb3) |

## Disperse (multisend)

`src/Disperse.sol` batch-distributes ETH or ERC20 tokens to many recipients in one transaction
(`disperseToken(token, recipients[], values[])`), used to pay out leaderboard prizes. It is a Solidity
0.8 reimplementation of the canonical [Disperse](https://etherscan.io/address/0xD152f549545093347A162Dce210e7293f1452150)
by banteg and keeps its **exact function selectors** (`disperseToken` = `0xc73a2d60`,
`disperseTokenSimple` = `0x51ba162c`, `disperseEther` = `0xe63d38ed`), so it is ABI-compatible with the
canonical contract and with disperse.app tooling.

Ethereum reuses the canonical deployment. On HyperEVM and MegaETH we deploy our own copy via
`script/DeployDisperse.s.sol`. The contract has no imports, so explorer verification is a single-file
paste (or `forge verify-contract <addr> src/Disperse.sol:Disperse ...`) and resolves to a full exact match.

| Chain          | Disperse Address                                                                                                       |
| -------------- | --------------------------------------------------------------------------------------------------------------------- |
| Ethereum (1)   | [0xD152f549545093347A162Dce210e7293f1452150](https://etherscan.io/address/0xD152f549545093347A162Dce210e7293f1452150) (canonical, reused) |
| HyperEVM (999) | [0x77Eb73e3496E1c9C29478471C8aDaB93Be6D1209](https://hyperevmscan.io/address/0x77Eb73e3496E1c9C29478471C8aDaB93Be6D1209) |
| MegaETH (4326) | [0x2ed4f1C6629FE64Ce3f78535109792544133344B](https://mega.etherscan.io/address/0x2ed4f1C6629FE64Ce3f78535109792544133344B) |
