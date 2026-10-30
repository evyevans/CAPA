import React, { useState } from 'react';
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom';

import { useAuth } from '../../hooks/useAuth';
import ParticleBackground from '../ParticleBackground';
import { AICore } from '../core/AICore';
import { useVoiceStore } from '../../stores/voiceStore';


const DashboardLayout: React.FC = () => {
  const { user, signOut } = useAuth();
  const [isSigningOut, setIsSigningOut] = useState(false);
  const location = useLocation();
  const navigate = useNavigate();
  const isSubPage = location.pathname !== '/dashboard';
  const isSpeaking = useVoiceStore((s) => s.isSpeaking);

  const handleSignOut = async () => {
    setIsSigningOut(true);
    await signOut();
  };

  return (
    <div className="relative w-screen h-screen bg-bg-primary transition-colors duration-300 overflow-hidden flex flex-col">
      {/* Shared background — same as original */}
      <div className="fixed inset-0 hex-grid-overlay pointer-events-none opacity-40" />
      <ParticleBackground />
      <div className="fixed inset-0 flex items-center justify-center pointer-events-none">
        <div
          className="w-[500px] h-[500px] rounded-full opacity-30"
          style={{ background: 'radial-gradient(circle, rgba(234, 179, 8, 0.12) 0%, rgba(234, 179, 8, 0.06) 40%, transparent 70%)' }}
        />
      </div>

      {/* Global AI Core - Always mounted to prevent WebGL compile lag */}
      <div
        className={`fixed inset-0 flex mt-[4%] items-center justify-center pointer-events-none z-0 transition-opacity duration-500 ${isSubPage ? (location.pathname === '/dashboard/settings' ? 'opacity-[0.12]' : 'opacity-0') : 'opacity-100'}`}
      >
        <div className="w-[280px] h-[280px] md:w-[380px] md:h-[380px] relative pointer-events-none">
          <AICore isSpeaking={isSpeaking} />
        </div>
      </div>

      {/* Top status bar */}
      <header className="relative z-20 flex items-center justify-between px-4 pt-safe pt-4 pb-3 border-b border-border/60 bg-bg-primary/50 backdrop-blur-md">
        <div className="flex items-center gap-3">
          {isSubPage && (
            <button
              onClick={() => navigate('/dashboard')}
              className="p-1 -ml-1 text-text-secondary hover:text-text-primary transition-colors flex items-center justify-center rounded-lg hover:bg-bg-surface"
              aria-label="Go back"
            >
              <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 19l-7-7m0 0l7-7m-7 7h18" />
              </svg>
            </button>
          )}
          <NavLink to="/dashboard" className="flex items-center gap-2 group cursor-pointer transition-opacity hover:opacity-80">
            <div className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
            <span className="font-orbitron font-bold text-gold-glow text-sm tracking-wide group-hover:text-gold-dark transition-colors">CAPA</span>
          </NavLink>
        </div>
        <div className="flex items-center gap-3">
          <span className="text-text-secondary text-xs font-inter truncate max-w-[130px]">{user?.email}</span>
          <NavLink
            to="/dashboard/settings"
            className={({ isActive }) =>
              `p-1 transition-colors ${isActive ? 'text-text-primary' : 'text-text-secondary hover:text-text-primary'}`
            }
            aria-label="Settings"
          >
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
          </NavLink>
          <button
            onClick={handleSignOut}
            disabled={isSigningOut}
            className="text-text-secondary hover:text-red-400 transition-colors p-1"
            aria-label="Sign out"
          >
            <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
            </svg>
          </button>
        </div>
      </header>

      {/* Main scrollable content */}
      <main className="relative z-10 flex-1 overflow-y-auto">
        <div role="note" className="px-4 py-2 text-xs text-yellow-300 bg-black/80">Visual demo · simulated tasks, replies and connectors · not connected to Hermes</div>
        <Outlet />
      </main>
    </div>
  );
};

export default DashboardLayout;
