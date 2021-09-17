const utils = require('./../test/utils');


module.exports = async ({getNamedAccounts, deployments}) => {
  const { deployer, owner, roundSubmitter } = await getNamedAccounts();
  
  const initialRelays = await utils.getInitialRelays();
  
  await deployments.deploy('Bridge', {
    from: deployer,
    log: true,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        methodName: 'initialize',
        args: [
          owner,
          roundSubmitter,
          3, // Minimum required signatures
          604800, // Relay TTL after round in seconds, 1 week
          0, // Initial round number
          Math.floor(Date.now() / 1000) + 604800, // Initial round end, after 1 week
          initialRelays.map(a => a.address), // Initial relays
        ],
      }
    }
  });
};

module.exports.tags = ['Deploy_Bridge'];
