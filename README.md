# ID PEPE (PEPE)

A fixed supply ERC-20 built with vendored OpenZeppelin Contracts v5.0.2.

| Deployment parameter | Value |
| --- | --- |
| Contract | `src/Token.sol:Token` |
| Name | `ID PEPE` |
| Symbol | `PEPE` |
| Decimals | `18` |
| Human-readable supply | `1,000,000,000 PEPE` |
| `totalSupply()` in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`, empty ABI encoding `0x`) |
| Initial recipient | Constructor `msg.sender` |
| Deployment value | `0` native currency |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Optimizer | Enabled, 200 runs |
| Metadata bytecode hash | `none` |

The constructor mints the entire supply once and emits the ERC-20 mint `Transfer`
event. A factory using CREATE or CREATE2 receives all tokens itself; the transaction
originator receives none automatically. Direct deployment assigns the supply to
the deploying account. Deploy the concrete contract, without a proxy or initializer.

## Behavior and assumptions

The requested token is interpreted as a standard, freely transferable ERC-20.
There are no taxes, transfer hooks, rebases, mint functions, public burns, owner,
pause, blacklist, seizure, upgrade mechanism, or privileged exemptions. The supply
remains fixed after construction. Transfers make no external calls and move the
exact amount, including transfers involving a factory, distributor, or pool manager.

`transfer`, `approve`, and `transferFrom` return `true` on success and revert with
OpenZeppelin ERC-6093 errors on invalid operations. Zero-value and self-transfers
are supported. Transfers to the zero address and approvals of the zero spender
are rejected. A finite allowance decreases on `transferFrom`; `uint256.max` is
treated as an unlimited allowance and is not decreased. `approve` replaces the
existing allowance. Explicit approvals emit `Approval`; delegated spending emits
`Transfer` and does not emit an additional `Approval` in this implementation.

Holders control their balances and allowances. Integrators should request only
needed allowances. When replacing an existing nonzero allowance, first revoke it
and confirm the revocation to mitigate the standard ERC-20 allowance replacement
race. A revocation cannot undo spending already included on chain.

## Build and verify locally

Install Foundry and Solidity 0.8.26 in the toolchain, then run:

```sh
forge build
forge test
forge fmt --check
```

All Solidity dependencies and their licenses are ordinary files under `lib/`;
there is no dependency download or submodule step. With the pinned compiler
available, builds and tests need no network, RPC, wallet, environment configuration,
FFI, or filesystem cheatcode permissions. Tests deploy fresh local instances in
`setUp` and do not share state or depend on execution order.

Unit and fuzz tests cover exact metadata and allocation, the mint event, immediate
caller ownership, CREATE2 address prediction, lossless distribution and pool-style
transfers, approvals, delegated spending, zero/self/full-balance transfers,
insufficient funds and allowances, invalid addresses, failure rollback, unsupported
administrative calls, and forbidden runtime opcodes. Stateful tests exercise
transfers, approvals, and delegated transfers across four holders and check supply
conservation and allowance accounting (128 runs, depth 64). Parameterized fuzz
tests run 256 cases each.

The factory fixture tests token transfer behavior only. It does not deploy Uniswap
or simulate pricing, liquidity accounting, or swaps. The supplied protected launch
harness belongs to the network and needs its factory/pool contracts, manifest, and
deployment environment; those are not present here. Its actual pool integration
checks remain the network verifier's responsibility.

## Deployment and operational responsibilities

The deployment artifact is `out/Token.sol/Token.json`. Its creation bytecode takes
no constructor arguments. An authorized deployment service can use that bytecode
with CREATE or CREATE2 and zero value. Rebuild with the pinned settings when
comparing runtime bytecode. The deployment network must support the Cancun target.

The network operator selects and verifies the chain, factory, pool manager,
CREATE2 salt, pairing, pool settings, pricing, and distribution destinations. These
parameters do not alter the token constructor. No chain addresses or economic
parameters were supplied, so none are invented here. There are no application
contracts or token-specific administrative setup transactions.

For IdentityMD custom launches, the factory is responsible for the prescribed
10% swarm distribution, pool funding, and forwarding the remainder. These are
factory operations after token construction. The network's manifest should identify
`src/Token.sol:Token`, use empty constructor arguments, and record the exact token
metadata and base-unit supply above; its economics must come from the authorized
launch configuration. The example seed amount in the local factory test is only
test data.

Before release, the operator should independently review the contract and launch
integration, verify the deployed source and runtime, and confirm metadata, supply,
and the factory's initial balance before distribution. Initial custody of the full
supply rests with the deployer/factory. There are no token admin keys or maintenance
jobs. Holders and operators are responsible for address accuracy, key custody, and
allowances. The token has no recovery facility for assets sent to it or other
unusable addresses, and it does not accept ordinary native-currency payments.

Local verification uses Foundry build, unit, fuzz, invariant, and formatting checks.
Slither and Mythril were not run. Tests do not constitute an independent security
audit. No transaction was broadcast and no wallet key is needed for this project.
