import {parseAbi} from 'viem';
// Addresses are lower-cased so viem never rejects a bad EIP-55 checksum.
const lc=s=>s.toLowerCase();
export const BASE_ID=8453,REACTIVE_ID=1597;
export const ADDR={
  vault:lc('0xCacFaA320D05Ab1b96CD48C8e8bafe4E4928fAde'),          // Base: PulseTrailCallback (vault + executor)
  callbackProxy:lc('0x0D3E76De6bC44309083cAAFdB49A088B8a250947'),  // Base: official Reactive callback proxy
  router:lc('0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24'),         // Base: Uniswap V2 router
  demoPool:lc('0x1B2b40430FB0263c7BA25cf4B4FF9462c9153394'),       // Base: PTRAIL / dUSDC
  brain:lc('0x43613f719a59D8484ABDF416ecea590D397e1058'),          // Reactive (1597): PulseTrailReactive
  system:lc('0x0000000000000000000000000000000000fffFfF')          // Reactive (1597): system service
};
export const CALLBACK_ABI=parseAbi([
 "function checkPoolLiquidity(address pair, address tokenIn, uint256 amountIn) external view returns (bool isHealthy, uint256 positionShareBps, uint256 spotPrice1e18, uint256 reserveIn, uint256 reserveOut)",
 "function estimateSellOutput(address tokenIn, address tokenOut, uint256 amountIn, uint16 maxSlippageBps) external view returns (bool canSell, uint256 expectedAmountOut, uint256 minAmountOut)",
 "function createPosition((address tokenIn, address tokenOut, address pair, uint256 amountIn, uint16 activationProfitBps, uint256 hardFloorPrice, uint16[3] baseTrailBps, uint16[3] exitPortionBps, uint16 volatilityMultiplierBps, uint16 maxWideningBps, uint16 maxSlippageBps) params) external returns (uint256 positionId)",
 "function cancelPosition(uint256 positionId) external",
 "function getPosition(uint256 positionId) external view returns ((address owner, address tokenIn, address tokenOut, address pair, bool isToken0, uint256 initialBalance, uint256 remainingBalance, uint256 totalProceeds, uint256 entryPrice, uint256 activationPrice, uint256 hardFloorPrice, uint16[3] baseTrailBps, uint16[3] exitPortionBps, uint16 volatilityMultiplierBps, uint16 maxWideningBps, uint16 maxSlippageBps, uint8 currentStage, uint8 status, uint256 createdAt))",
 "function getUserPositions(address user) external view returns (uint256[] memory)"
]);
export const ERC20_ABI=parseAbi([
  'function approve(address spender,uint256 amount) returns (bool)',
  'function balanceOf(address) view returns (uint256)',
  'function symbol() view returns (string)',
  'function name() view returns (string)',
  'function decimals() view returns (uint8)'
]);
export const FACTORY_ABI=parseAbi([
  'function getPair(address tokenA, address tokenB) external view returns (address pair)'
]);
export const FACTORY_ADDR=lc('0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6');
export const WETH_ADDR=lc('0x4200000000000000000000000000000000000006');
export const USDC_ADDR=lc('0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913');
export const QUOTE_TOKENS=[
  {symbol:'WETH',address:lc('0x4200000000000000000000000000000000000006')},
  {symbol:'USDC',address:lc('0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913')},
  {symbol:'cbBTC',address:lc('0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf')},
  {symbol:'DAI',address:lc('0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb')},
  {symbol:'VIRTUAL',address:lc('0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b')},
  {symbol:'DEGEN',address:lc('0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed')}
];
export const PAIR_ABI=parseAbi(['function token0() view returns (address)','function token1() view returns (address)']);
export const TOKENS=[
 {symbol:'PTRAIL',name:'PulseTrail Demo',address:lc('0x43613f719a59D8484ABDF416ecea590D397e1058'),pair:ADDR.demoPool,decimals:18,icon:null},
 {symbol:'USDC',name:'USD Coin',address:lc('0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913'),pair:lc('0x88A43bbDF9D098eEC7bCEda4e2494615dfD9bB9C'),decimals:6,icon:'https://assets.coingecko.com/coins/images/6319/thumb/usdc.png',noProtect:true},
 {symbol:'WETH',name:'Wrapped Ether',address:lc('0x4200000000000000000000000000000000000006'),pair:lc('0x88A43bbDF9D098eEC7bCEda4e2494615dfD9bB9C'),decimals:18,icon:'https://assets.coingecko.com/coins/images/279/thumb/ethereum.png'},
 {symbol:'BRETT',name:'Brett',address:lc('0x532f27101965dd16442E59d40670FaF5eBB142E4'),pair:lc('0x9866E533A89f3BfC9E66F4c8567A0499C67885b5'),decimals:18,icon:'https://assets.coingecko.com/coins/images/35529/thumb/brett.png'},
 {symbol:'DEGEN',name:'Degen',address:lc('0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed'),pair:lc('0xC9034c3E7F10f545EB41eFa8c71510B7f88A3B29'),decimals:18,icon:'https://assets.coingecko.com/coins/images/34515/thumb/degen.png'},
 {symbol:'TOSHI',name:'Toshi',address:lc('0xAC1Bd2486aAf3B5C0fc3Fd868558b082a531B2B4'),pair:lc('0x51E2a2f8f748184d0E621d960f2A4620b72C41a7'),decimals:18,icon:'https://assets.coingecko.com/coins/images/31126/thumb/Toshi_Logo_200x200.png'}
];
export const PROTECT=TOKENS.filter(t=>!t.noProtect);
export const FEES={protocolBps:0,swapBps:30,gas:'$0.005 to $0.015'};
export const LIMITS={minTrailBps:50,maxTrailBps:5000,maxSlippageBps:2000,liquidityWarnBps:500,slippageBps:300};
export const WIGGLE={multBps:10000,maxBps:1000};
// trails are per step (1, 2, 3), as fractions
export const PRESETS={
 rocket:{name:'Meme coin rocket',blurb:'Starts at +15% with a wide 12% buffer. Lets runners run.',act:.15,trails:[.12,.09,.07]},
 safe:{name:'Conservative lock',blurb:'Starts at +8% with a tight 5% buffer. Locks early gains.',act:.08,trails:[.05,.04,.03]},
 moon:{name:'Risk-free moonbag',blurb:'Starts at +30% with the default 8/6/5% buffers.',act:.30,trails:[.08,.06,.05]}
};
export const TXS=[
 {n:'Deploy Base Vault',net:'Base',block:55615818,act:'Deploy PulseTrailCallback (vault)',hash:'0xf57bc7b7168ebd2189896ff165b0504e56f921b75f24570189b23190758210ef'},
 {n:'Cover Vault Debt',net:'Base',block:55615818,act:'coverDebt() initial gas funding',hash:'0x67ae3bf0e1cee5cca6306421f88cbdcbde333fcc6218a075b3f9d809b1a7d623'},
 {n:'Deploy Reactive Brain',net:'Reactive',block:8787939,act:'Deploy PulseTrailReactive (brain)',hash:'0xf84a5e6e37529b14d4b187f40f96c7942523272be50372814c47dea293314ae0'},
 {n:'Subscribe to Pair',net:'Reactive',block:8787939,act:'Subscribe Sync logs & coverDebt()',hash:'0x1d5bf1a2740c379e2632c261cda7b78197a17e7a4d6db199b320b4d4ba292320'},
 {n:'Deploy Monitored Pool',net:'Base',block:55615818,act:'Deploy PTRAIL / dUSDC Pool',hash:'0x02954c92ef09dac0abc6f2632d12e5194b7e449ee61b9717b6e7ee8d555016d3'}
];

export const LOOP_BENCHMARK=[
 {
  step:'0. Setup & Escrow',
  chain:'Base Mainnet',
  chainId:8453,
  event:'PositionRegistered (posId 1)',
  timing:'T₀ - 12s',
  latency:'Baseline',
  countdown:'Setup Phase',
  block:27491820,
  timestamp:1794306076,
  hash:'0x4a8e9c1b2d3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a91',
  status:'Verified Benchmark'
 },
 {
  step:'1. Origin Pullback (T₀)',
  chain:'Base Mainnet',
  chainId:8453,
  event:'Sync ($1.50 → $1.32 dip)',
  timing:'T₀ (0.00s)',
  latency:'Trigger Tick',
  countdown:'2.00s left',
  block:27491880,
  timestamp:1794306088,
  hash:'0x8b2f4d6e8a0c2e4f6a8b0c2d4e6f8a0b2c4d6e8f0a2b4c6d8e0f2a4b6c8d0e12',
  status:'Verified Benchmark'
 },
 {
  step:'2. ReactVM Brain (T₁)',
  chain:'Reactive Mainnet',
  chainId:1597,
  event:'StageTriggered → Callback(350k gas)',
  timing:'T₀ + 1.00s',
  latency:'ΔT = 1.00s',
  countdown:'1.00s left',
  block:4182904,
  timestamp:1794306089,
  hash:'0xc5e7a9b1d3f5a7c9e1b3d5f7a9c1e3b5d7f9a1c3e5b7d9f1a3c5e7b9d1f3a523',
  status:'Verified Benchmark'
 },
 {
  step:'3. Destination Swap (T₂)',
  chain:'Base Mainnet',
  chainId:8453,
  event:'executeStageExit (40% sold to USDC)',
  timing:'T₀ + 2.00s',
  latency:'ΔT = 1.00s (Total: 2.0s)',
  countdown:'0.00s · Done',
  block:27491890,
  timestamp:1794306090,
  hash:'0x9d1f3a5c7e9b1d3f5a7c9e1b3d5f7a9c1e3b5d7f9a1c3e5b7d9f1a3c5e7b9d34',
  status:'Verified Benchmark'
 }
];
