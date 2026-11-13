// Master Timeline & Audio-Visual Synchronization Spec for PulseTrail Demo Video
// Single source of truth for both Remotion React visuals and synthesized 48kHz soundtrack + UI SFX.
// Tempo: 120 BPM (2 beats/sec = 15 frames/beat @ 30fps, 1 bar = 2.0s = 60 frames)
// Total Duration: 2 minutes 36 seconds (156.0s = 78 bars = 4,680 frames @ 30fps)

export const VIDEO_META = {
  fps: 30,
  bpm: 120,
  framesPerBeat: 15,
  framesPerBar: 60,
  totalBars: 78,
  durationInFrames: 4680, // 156.0 seconds (2m 36s)
  desktop: { width: 1920, height: 1080 },
  vertical: { width: 1080, height: 1920 },
};

export const BRAND = {
  stageBg: '#0b0e14',
  bg: '#fafafa',
  ink: '#111111',
  card: '#ffffff',
  mut: '#555555',
  red: '#e02424',
  grn: '#059669',
  neonGrn: '#00f59b',
  pur: '#6a3df0',
  org: '#f58220',
  dot: '#e2e1db',
  blueNote: '#1d4ed8',
};

export const SCENES = [
  {
    id: 'cover',
    stepIndex: 0,
    title: 'Cover & Intro',
    startFrame: 0,
    endFrame: 239, // 00:00 - 00:08 (8s, Bars 1-4)
    route: 'home',
    captionNumber: '00',
    captionLabel: 'AUTONOMOUS STOP-LOSS',
    captionHeadline: 'Ride. Ratchet. Sleep.',
    captionSub: 'Non-custodial trailing protection across Base (8453) & Reactive (1597).',
    subtitle: 'PulseTrail: autonomous smart stop-losses on Base that ratchet up as your tokens climb, and cash out into USDC in three steps.',
  },
  {
    id: 'hero_intro',
    stepIndex: 1,
    title: '1 SIMULATE',
    startFrame: 240,
    endFrame: 599, // 00:08 - 00:20 (12s, Bars 5-10)
    route: 'home',
    captionNumber: '01',
    captionLabel: 'NON-CUSTODIAL PROTECTION',
    captionHeadline: 'Ride the pump. Lock the gains.',
    captionSub: 'Zero protocol fees, zero Telegram bot risk, and your keys never leave your wallet.',
    subtitle: 'Traditional stop-losses get wicked out early or require handing your private keys to a Telegram bot. PulseTrail runs entirely on-chain.',
  },
  {
    id: 'simulate',
    stepIndex: 1,
    title: '1 SIMULATE',
    startFrame: 600,
    endFrame: 1139, // 00:20 - 00:38 (18s, Bars 11-19)
    route: 'home',
    captionNumber: '01',
    captionLabel: 'PROFIT-ACTIVATED RATCHET',
    captionHeadline: 'Play a simulated pump',
    captionSub: 'Waits for +15% profit, trails every peak, and scales out 40% / 30% / 30% into USDC.',
    subtitle: 'Click Play a simulated pump: protection stays dormant until plus fifteen percent, ratchets up with every new peak, and scales out forty, thirty, and thirty percent into USDC.',
  },
  {
    id: 'why_compare',
    stepIndex: 1,
    title: '1 SIMULATE',
    startFrame: 1140,
    endFrame: 1559, // 00:38 - 00:52 (14s, Bars 20-26)
    route: 'home_why',
    captionNumber: '01',
    captionLabel: 'WHY PULSETRAIL WINS',
    captionHeadline: 'Three steps. No jargon.',
    captionSub: 'Beats custodial Telegram bots and manual panic-selling on 3 AM pumps and wicks.',
    subtitle: 'Scroll down to compare: Three steps, no jargon. When a three AM pump or sudden wick hits, PulseTrail widens its cushion and banks gains while you sleep.',
  },
  {
    id: 'configure_token',
    stepIndex: 2,
    title: '2 CONFIGURE',
    startFrame: 1560,
    endFrame: 2039, // 00:52 - 01:08 (16s, Bars 27-34)
    route: 'app',
    captionNumber: '02',
    captionLabel: 'TOKEN & POOL DISCOVERY',
    captionHeadline: 'Pick token & deposit size',
    captionSub: 'Choose PTRAIL, WETH, BRETT, DEGEN, or paste any Base Uniswap V2 / Aerodrome pair.',
    subtitle: 'Open Protect to pick your token and deposit size: select PTRAIL, WETH, BRETT, or DEGEN on Base, auto-detect its liquidity pool, and enter ten thousand tokens.',
  },
  {
    id: 'configure_preset',
    stepIndex: 2,
    title: '2 CONFIGURE',
    startFrame: 2040,
    endFrame: 2459, // 01:08 - 01:22 (14s, Bars 35-41)
    route: 'app',
    captionNumber: '02',
    captionLabel: 'STRATEGY PRESETS & ESTIMATOR',
    captionHeadline: 'Meme coin rocket preset',
    captionSub: 'Starts at +15% with 12% / 9% / 7% buffers — estimator projects ~$1,621 (+62%).',
    subtitle: 'Compare Conservative lock and Meme coin rocket: the live estimator calculates your exact three-step USDC payout after the pool swap fee, projecting sixteen hundred twenty-one dollars.',
  },
  {
    id: 'shield_checks',
    stepIndex: 3,
    title: '3 SHIELD',
    startFrame: 2460,
    endFrame: 2879, // 01:22 - 01:36 (14s, Bars 42-48)
    route: 'app',
    captionNumber: '03',
    captionLabel: 'PRE-FLIGHT RISK SHIELD',
    captionHeadline: 'On-chain safety verification',
    captionSub: 'Checks honeypot sellability, pool share (0.42% < 5%), and reserve depth ($2.4M).',
    subtitle: 'Before a single token is deposited, the on-chain Safety Check verifies honeypot sellability, pool share impact under five percent, and healthy reserve depth.',
  },
  {
    id: 'shield_wiggle',
    stepIndex: 3,
    title: '3 SHIELD',
    startFrame: 2880,
    endFrame: 3239, // 01:36 - 01:48 (12s, Bars 49-54)
    route: 'app',
    captionNumber: '03',
    captionLabel: 'VOLATILITY-ADAPTIVE BUFFER',
    captionHeadline: 'Smart wiggle room (+10%)',
    captionSub: '8-tick rolling volatility engine widens trail (12% -> 22%) during violent wicks.',
    subtitle: 'Switch to Pro mode and enable Smart wiggle room: an eight-tick rolling volatility buffer automatically widens your stop during wild market swings.',
  },
  {
    id: 'vault',
    stepIndex: 4,
    title: '4 VAULT',
    startFrame: 3240,
    endFrame: 3659, // 01:48 - 02:02 (14s, Bars 55-61)
    route: 'app',
    captionNumber: '04',
    captionLabel: 'ONE-CLICK VAULT ESCROW',
    captionHeadline: 'Activate auto-protection',
    captionSub: 'Deposits into Base Mainnet vault (0xCacF...fAde) with ~$0.008 gas in ~200ms.',
    subtitle: 'Click Activate auto-protection: approve and register Position Number One in the Base Mainnet vault in a two-hundred-millisecond Flashblock for under a cent.',
  },
  {
    id: 'inspect',
    stepIndex: 5,
    title: '5 INSPECT',
    startFrame: 3660,
    endFrame: 4139, // 02:02 - 02:18 (16s, Bars 62-69)
    route: 'positions',
    captionNumber: '05',
    captionLabel: 'LIVE POSITION INSPECTOR',
    captionHeadline: 'Real-time peak & viral proof',
    captionSub: 'Monitors PTRAIL #1 on-chain, banks +552 USDC on Step 1, and shares 1-click proof.',
    subtitle: 'Under My positions, watch the Reactive Brain ratchet your live peak to one dollar eighty-four, bank five hundred fifty-two USDC on Step One, and copy your shareable proof.',
  },
  {
    id: 'proof',
    stepIndex: 6,
    title: '6 PROOF',
    startFrame: 4140,
    endFrame: 4679, // 02:18 - 02:36 (18s, Bars 70-78)
    route: 'proof',
    captionNumber: '06',
    captionLabel: 'VERIFIED ON-CHAIN LOOP',
    captionHeadline: '2.0s cross-chain execution',
    captionSub: 'Base Sync (T0) -> Reactive Brain (T1, 1.0s) -> Base Callback Swap (T2, 1.0s).',
    subtitle: 'Every contract and two-second cross-chain callback is verified on BaseScan and ReactScan. Test it yourself with zero risk at pulsetrail.app — Ride. Ratchet. Sleep.',
  },
];
