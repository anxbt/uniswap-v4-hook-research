
# Uniswap v4 Hook Learnings (Indexed)

This document is a structured, indexed collection of learnings and pitfalls from building Uniswap v4 hooks. Each section is dedicated to a specific hook or pattern, so future hooks can be added as new sections.

---

## Index

1. [Fee Modifier Hook](#fee-modifier-hook)
2. [TWAP/Volatility Hook](#twapvolatility-hook) *(planned)*
3. [Other Hooks](#other-hooks) *(planned)*

---

## 1. Fee Modifier Hook

### Introduction
My first Uniswap v4 hook: a fee modifier that dynamically adjusts swap fees. This section covers hook mechanics, fee logic, delta, state, and testing.

### Key Learnings

**What is a Hook?**
- Hooks are custom contracts that Uniswap v4 pools call at specific lifecycle points (before/after swap, liquidity changes, etc.).
- They allow you to inject custom logic (e.g., dynamic fees, analytics, access control) into the pool’s operation.

**Overriding Fees**
- To override a pool’s fee, your hook must:
  - Return a `uint24` with bit 23 set: `(1 << 23) | feeBps`
  - The pool must be created with the dynamic fee flag.
  - The fee value must be within protocol bounds (≤ 1,000,000 BPS).
- If any condition is missed, the override is ignored.

**Understanding Delta**
- `BeforeSwapDelta` lets a hook adjust swap amounts before execution.
- Returning `ZERO_DELTA` means “don’t touch the amounts.”
- Only use non-zero delta if you want to actively change swap amounts (not just fees).

**State Management**
- Use mappings keyed by `PoolId` to isolate state per pool.
- Store only what’s needed (e.g., counters, observations).
- Always ensure state updates are atomic and pool-specific.

**Testing Hooks**
- Unit tests: check fee logic, state changes, and edge cases.
- Fuzz tests: randomize swap amounts to catch overflows and logic bugs.
- Invariant tests: ensure properties like “count never decreases” or “fee always within bounds” hold for any sequence of actions.

### Pitfalls & Gotchas

- **Fee Override Ignored:** If bit 23 isn’t set or the pool isn’t dynamic, your fee override does nothing (no error, just ignored).
- **Delta Confusion:** Delta is only relevant if you want to change swap amounts. For fee-only hooks, always return `ZERO_DELTA`.
- **Fuzzing Overflows:** Fuzzing with unbounded amounts can cause arithmetic overflows in pool math. Always bound your inputs to safe ranges.
- **State Isolation:** Forgetting to key state by `PoolId` can cause cross-pool bugs and data leaks.
- **Solidity Type Limits:** Be aware of `int128`/`uint128` limits in Uniswap’s math. Don’t exceed these in your tests or logic.

### Advice & Best Practices

- Always test edge cases: multiple swaps, very small/large amounts, and protocol limits.
- Use fuzz and invariant testing to catch subtle bugs and ensure protocol safety.
- Clamp all computed fees to protocol max/min to avoid accidental reverts or economic attacks.
- Document your hook’s logic, state, and assumptions clearly for future maintainers (and yourself!).
- Defensive coding: handle missing data gracefully, fallback to safe defaults.

### Conclusion

Building a Uniswap v4 hook taught me about protocol internals, safe state management, and robust testing. Next, I want to explore hooks that use TWAPs and volatility for dynamic fee logic, and learn more about advanced stateful hooks.

---

## 2. TWAP/Volatility Hook *(planned)*

*Section reserved for future learnings about TWAP and volatility-based hooks.*

---

## 3. Other Hooks *(planned)*

*Section reserved for future hooks and patterns.*
