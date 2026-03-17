# Damn Vulnerable DeFi

## Quick use

1. Put write-ups in `src/<challenge-name>/write-up`
2. Put solutions in `test/<challenge-name>/<ChallengeName>.t.sol`
3. Run a solution:

   `forge test --mp test/<challenge-name>/<ChallengeName>.t.sol`

   > In challenges that restrict the number of transactions, you might need to run the test with the `--isolate` flag.

## Progress

- [x] [unstoppable](src/unstoppable/write-up.md)
- [x] [naive-receiver](src/naive-receiver/write-up.md)
- [x] [truster](src/truster/write-up.md)
- [x] [side-entrance](src/side-entrance/write-up.md)
- [ ] the-rewarder
- [x] [selfie](src/selfie/write-up.md)
- [ ] compromised
- [x] [puppet](src/puppet/write-up.md)
- [x] [puppet-v2](src/puppet-v2/write-up.md)
- [x] [free-rider](src/free-rider/write-up.md)
- [x] [backdoor](src/backdoor/write-up.md)
- [x] [climber](src/climber/write-up.md)
- [ ] wallet-mining
- [ ] puppet-v3
- [x] [abi-smuggling](src/abi-smuggling/write-up.md)
- [ ] shards
- [ ] curvy-puppet
- [ ] withdrawal
