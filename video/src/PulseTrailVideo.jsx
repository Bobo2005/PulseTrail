import React from 'react';
import { AbsoluteFill, Audio, interpolate, spring, useCurrentFrame, useVideoConfig } from 'remotion';
import { BRAND, SCENES } from './timeline.js';
import { PATH, simulate, estimate, DEMO_USD } from '../../frontend/src/lib/sim.js';
import { PRESETS, TXS, LOOP_BENCHMARK } from '../../frontend/src/config/contracts.js';

const STEPS_BAR = [
  '1 SIMULATE',
  '2 CONFIGURE',
  '3 SHIELD',
  '4 VAULT',
  '5 INSPECT',
  '6 PROOF',
];

export const PulseTrailVideo = ({ orientation = 'desktop' }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const isVertical = orientation === 'vertical' || height > width;

  const activeScene =
    SCENES.find((s) => frame >= s.startFrame && frame <= s.endFrame) ||
    SCENES[SCENES.length - 1];
  const localFrame = frame - activeScene.startFrame;
  const sceneDuration = activeScene.endFrame - activeScene.startFrame + 1;

  // Progressive karaoke subtitle word illumination
  const words = activeScene.subtitle.split(' ');
  const activeWordIdx = Math.floor(
    interpolate(localFrame, [0, sceneDuration * 0.88], [0, words.length], {
      extrapolateRight: 'clamp',
    })
  );

  // Camera spring transform per scene
  let camScale = 1;
  let camX = 0;
  let camY = 0;
  if (activeScene.id === 'simulate' && frame >= 175) {
    const p = spring({ frame: frame - 175, fps, config: { damping: 16, stiffness: 90 } });
    camScale = interpolate(p, [0, 1], [1, 1.24]);
    camX = interpolate(p, [0, 1], [0, -140]);
    camY = interpolate(p, [0, 1], [0, -20]);
  } else if (activeScene.id === 'configure') {
    const p = spring({ frame: localFrame, fps, config: { damping: 16, stiffness: 90 } });
    camScale = interpolate(p, [0, 1], [1, 1.18]);
    camX = interpolate(p, [0, 1], [0, 110]);
  } else if (activeScene.id === 'shield') {
    const p = spring({ frame: localFrame, fps, config: { damping: 16, stiffness: 90 } });
    camScale = interpolate(p, [0, 1], [1.18, 1.26]);
    camX = frame < 935 ? -130 : 120;
  }

  // Simulated chart index for Scene 1
  const simIdx =
    activeScene.id === 'simulate'
      ? Math.floor(
          interpolate(frame, [175, 390], [0, 79], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          })
        )
      : 79;
  const simCfg = {
    tok: 'PTRAIL',
    amount: '10000',
    preset: 'rocket',
    act: PRESETS.rocket.act,
    trails: PRESETS.rocket.trails,
    wiggle: frame >= 1010,
  };
  const simState = simulate(simIdx, simCfg);
  const estState = estimate(DEMO_USD, simCfg);

  return (
    <AbsoluteFill
      style={{
        backgroundColor: BRAND.stageBg,
        fontFamily: "'Bricolage Grotesque', 'Segoe UI', sans-serif",
        color: BRAND.ink,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        padding: isVertical ? '48px 28px' : '36px 64px',
      }}
    >
      <Audio src="/soundtrack.wav" />

      {/* Cover Card on Scene 0 (Frame 0 is 100% thumbnail ready) */}
      {activeScene.id === 'cover' ? (
        <div
          style={{
            background: BRAND.bg,
            border: '4px solid #111',
            borderRadius: 24,
            padding: isVertical ? '56px 40px' : '64px 76px',
            boxShadow: '14px 18px 0 #000',
            transform: 'rotate(-0.6deg)',
            maxWidth: isVertical ? 960 : 1280,
            width: '100%',
            position: 'relative',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: 24, marginBottom: 16 }}>
            <img
              src="/logo.png"
              alt="PulseTrail"
              style={{ width: 84, height: 86, imageRendering: 'pixelated' }}
            />
            <h1 style={{ fontSize: isVertical ? 82 : 108, fontWeight: 900, margin: 0, letterSpacing: '-0.04em' }}>
              PULSETRAIL
            </h1>
            <span
              style={{
                background: BRAND.neonGrn,
                border: '3px solid #111',
                borderRadius: 10,
                padding: '6px 16px',
                fontFamily: "'JetBrains Mono', monospace",
                fontWeight: 800,
                fontSize: 24,
              }}
            >
              BASE
            </span>
          </div>
          <p style={{ fontSize: isVertical ? 30 : 34, color: BRAND.mut, margin: '0 0 36px' }}>
            Autonomous smart stop-losses for Base that ratchet up and cash out in 3 steps.
          </p>
          <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap', alignItems: 'center' }}>
            <span style={{ border: '3px solid #111', padding: '8px 18px', fontWeight: 800 }}>
              BASE MAINNET · 8453
            </span>
            <span style={{ border: '3px solid #6a3df0', color: '#6a3df0', padding: '8px 18px', fontWeight: 800 }}>
              REACTIVE BRAIN · 1597
            </span>
            <span style={{ border: '3px solid #059669', color: '#059669', padding: '8px 18px', fontWeight: 800 }}>
              SUB-2.0S FULL LOOP
            </span>
            <span style={{ color: BRAND.blueNote, fontStyle: 'italic', fontSize: 30, marginLeft: 'auto' }}>
              a walkthrough of the live app
            </span>
          </div>
        </div>
      ) : (
        /* Browser Device Frame */
        <div
          style={{
            width: '100%',
            height: isVertical ? '76%' : '82%',
            background: BRAND.bg,
            borderRadius: 20,
            border: '3px solid #2b2f3a',
            overflow: 'hidden',
            display: 'flex',
            flexDirection: 'column',
            boxShadow: '0 28px 70px rgba(0,0,0,0.65)',
          }}
        >
          {/* MacOS Browser Bar + 6-Step Progress Tracker */}
          <div
            style={{
              background: '#171922',
              color: '#f2f0ea',
              height: 52,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              padding: '0 20px',
              fontFamily: "'JetBrains Mono', monospace",
              fontSize: 13,
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span style={{ width: 12, height: 12, borderRadius: '50%', background: '#ef4444' }} />
              <span style={{ width: 12, height: 12, borderRadius: '50%', background: '#f59e0b' }} />
              <span style={{ width: 12, height: 12, borderRadius: '50%', background: '#10b981' }} />
              <span
                style={{
                  background: '#252936',
                  padding: '4px 18px',
                  borderRadius: 8,
                  marginLeft: 10,
                }}
              >
                🔒 pulsetrail.app/#{activeScene.route}
              </span>
            </div>
            <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
              {STEPS_BAR.map((label, idx) => {
                const stepNum = idx + 1;
                const done = stepNum < activeScene.stepIndex;
                const cur = stepNum === activeScene.stepIndex;
                return (
                  <span
                    key={label}
                    style={{
                      padding: '4px 10px',
                      borderRadius: 6,
                      border: cur ? '1.5px solid #00f59b' : '1px solid transparent',
                      color: cur ? '#fff' : done ? '#f59e0b' : '#777',
                      fontWeight: 700,
                    }}
                  >
                    {done ? '✓ ' + label.slice(2) : label}
                  </span>
                );
              })}
            </div>
          </div>

          {/* Camera Viewport inside Browser */}
          <div
            style={{
              flex: 1,
              position: 'relative',
              overflow: 'hidden',
              transform: `scale(${camScale}) translate(${camX}px, ${camY}px)`,
              transformOrigin: 'center center',
              padding: '24px 36px',
            }}
          >
            {/* Dynamic Route Content */}
            <div>
              <h2>{activeScene.captionHeadline}</h2>
              <p>{activeScene.captionSub}</p>
              <pre style={{ fontSize: 12 }}>
                Stage: {simState.stage} | Price: ${simState.price.toFixed(2)} | Est: ${Math.round(estState.total)} | TXS: {TXS.length} | Benchmarks: {LOOP_BENCHMARK.length}
              </pre>
            </div>
          </div>
        </div>
      )}

      {/* Progressive Bottom Subtitles */}
      <div
        style={{
          marginTop: 22,
          textAlign: 'center',
          maxWidth: isVertical ? 960 : 1480,
          fontSize: isVertical ? 28 : 25,
          fontWeight: 700,
          lineHeight: 1.38,
        }}
      >
        {words.map((w, idx) => (
          <span
            key={idx}
            style={{
              color: idx <= activeWordIdx ? '#ffffff' : 'rgba(255,255,255,0.36)',
              marginRight: 7,
            }}
          >
            {w}
          </span>
        ))}
      </div>
    </AbsoluteFill>
  );
};

