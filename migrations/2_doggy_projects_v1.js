const DoggyProjectsV1 = artifacts.require('DoggyProjectsV1');

const { deployProxy } = require('@openzeppelin/truffle-upgrades');

module.exports = async function (deployer) {
    await deployProxy(DoggyProjectsV1, ['0x15D6F888c24C491A9b21f47627565E2330ff23c6'], { deployer, initializer: 'initialize' });
};