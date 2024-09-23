# Foundry Stablecoin

## Project Description
Foundry Stablecoin is a simple Stablecoin contract based on the MakerDAO algorithmic Stablecoin DAI overcollateralized mechanism. It is written in the Foundry framework, with deployment scripts and tests. The project uses Chainlink price feeds for real-time USD price of collateral assets.

## Installation Instructions
Make sure you have Foundry and Git installed. Then, clone the repository locally:

```shell
$ git clone <repository_url>
```

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil local node

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/DeployDSC.s.sol:DeployDSC --rpc-url <your_rpc_url> --private-key <your_private_key>
```

## Contribution Guidelines
Please fork the repository and create a pull request for any changes you would like to contribute. Ensure that your code follows the existing style and passes all tests.

## Warning
This code has not been audited. Use it at your own risk and be cautious if deploying it in a production environment.

## License
This project is licensed under the MIT License.