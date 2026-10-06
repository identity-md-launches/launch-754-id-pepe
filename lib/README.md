# Vendored dependencies

These are ordinary source files, not Git submodules. No package manager or network
access is required to resolve the imports. Upstream Solidity files are unmodified.

| Package | Pinned release | Included files | License |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | `v5.0.2` | ERC20 and its complete transitive import closure | MIT |
| forge-std | `v1.9.7` | `src/` (test utilities) | MIT / Apache-2.0 |

Sources:

- `https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2`
  — archive SHA-256 `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`
- `https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7`
  — archive SHA-256 `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`

Original license files accompany each package. `remappings.txt` resolves every
project import to these local sources. OpenZeppelin's internal mint and burn helpers
are not public token entry points; `Token` invokes mint only in its constructor.
