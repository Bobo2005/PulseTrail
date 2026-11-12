import React, {useState, useEffect} from 'react';
import ReactDOM from 'react-dom/client';
import '@rainbow-me/rainbowkit/styles.css';
import {RainbowKitProvider, getDefaultConfig, lightTheme, darkTheme} from '@rainbow-me/rainbowkit';
import {WagmiProvider, http} from 'wagmi';
import {base} from 'wagmi/chains';
import {QueryClient, QueryClientProvider} from '@tanstack/react-query';
import App from './App.jsx';
import './styles.css';

const config = getDefaultConfig({
  appName: 'PulseTrail',
  projectId: import.meta.env.VITE_WC_PROJECT_ID || 'demo',
  chains: [base],
  transports: { [base.id]: http() }
});

const qc = new QueryClient();

function getInitialTheme() {
  if (typeof window === 'undefined') return 'dark';
  const saved = localStorage.getItem('theme');
  if (saved === 'light' || saved === 'dark') return saved;
  return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function Root() {
  const [theme, setTheme] = useState(getInitialTheme);

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    try {
      localStorage.setItem('theme', theme);
    } catch (e) {}
  }, [theme]);

  useEffect(() => {
    const mq = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)');
    if (!mq) return;
    const handler = (e) => {
      if (!localStorage.getItem('theme')) {
        setTheme(e.matches ? 'dark' : 'light');
      }
    };
    mq.addEventListener?.('change', handler);
    return () => mq.removeEventListener?.('change', handler);
  }, []);

  const toggleTheme = () => {
    setTheme(prev => (prev === 'light' ? 'dark' : 'light'));
  };

  const rkTheme = theme === 'light'
    ? lightTheme({ accentColor: '#111', accentColorForeground: '#fff', borderRadius: 'medium' })
    : darkTheme({ accentColor: '#00f59b', accentColorForeground: '#111', borderRadius: 'medium' });

  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={qc}>
        <RainbowKitProvider theme={rkTheme}>
          <App theme={theme} onToggleTheme={toggleTheme} />
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<Root />);
