# PulseTrail frontend (React 18 + Vite)

    cp .env.example .env     # add your WalletConnect project id
    npm install --legacy-peer-deps
    npm run dev              # or: npm run build

Routes (plain hashes): #home, #app, #positions, #proof, #docs

- `src/config/contracts.js`  addresses, ABI, tokens, fees, limits, presets, proof txs
- `src/lib/sim.js`           demo simulator mirroring the contract's exit rules
- `src/components/*`         Header, StrategyBuilder, RatchetChart, LadderStepper, RiskShield, PositionInspector, ProofTable, Footer
- `src/content/*.html`       static home explainer and docs copy

## Verify before launch
- PTRAIL token address equals the Reactive brain address in contracts.js. Confirm it.
- Proof-page tx hashes look like placeholders. Replace with real ones.
- Assumed: status 0 active / 1 completed / 2 cancelled; hardFloorPrice 0 = disabled.
