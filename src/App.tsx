import React, { useEffect } from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { useAuth } from './hooks/useAuth';
import { useThemeStore } from './stores/themeStore';
import LoginView from './components/auth/LoginView';
import DashboardLayout from './components/dashboard/DashboardLayout';
import CommandCenter from './components/dashboard/CommandCenter';
import ActivityFeed from './components/dashboard/ActivityFeed';
import Settings from './pages/Settings';

// ── Guest access key — set in localStorage to bypass auth ──────────────────
export const GUEST_KEY = 'capa_guest_access';

// This gate controls demo navigation only; it is not authentication.
const ProtectedRoute: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { session } = useAuth();
  return session ? <>{children}</> : <Navigate to="/login" replace />;
};

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const { theme } = useThemeStore();

  useEffect(() => {
    const root = document.documentElement;
    root.classList.remove('theme-night', 'theme-colorblind', 'theme-system');

    if (theme === 'night') root.classList.add('theme-night');
    if (theme === 'colorblind') root.classList.add('theme-colorblind');
    if (theme === 'system') root.classList.add('theme-system');
  }, [theme]);

  useEffect(() => {
    document.body.className = 'antialiased';
  }, []);

  return <>{children}</>;
}

function App() {
  return (
    <ThemeProvider>
      <Routes>
        {/* Auth */}
        <Route path="/login" element={<LoginView />} />

        <Route path="/auth/callback" element={<Navigate to="/login" replace />} />
        <Route path="/onboarding" element={<Navigate to="/login" replace />} />
        <Route path="/pricing" element={<Navigate to="/login" replace />} />

        <Route
          path="/dashboard"
          element={
            <ProtectedRoute>
              <DashboardLayout />
            </ProtectedRoute>
          }
        >
          <Route index element={<CommandCenter />} />
          <Route path="activity" element={<ActivityFeed />} />
          <Route path="fleet" element={<ComingSoon title="Agent Fleet" icon="🤖" description="Manage your AI agent personas, behavioral rules, and deployment configs." />} />
          <Route path="analytics" element={<ComingSoon title="ROI Analytics" icon="📊" description="Deep-dive into agent performance, hours saved, and revenue attributed." />} />
          <Route path="settings" element={<Settings />} />
        </Route>

        {/* Default redirect */}
        <Route path="*" element={<Navigate to="/dashboard" replace />} />
      </Routes>
    </ThemeProvider>
  );
}

// Simple placeholder for future pages
const ComingSoon: React.FC<{ title: string; icon: string; description: string }> = ({ title, icon, description }) => (
  <div className="flex flex-col items-center justify-center min-h-[60vh] text-center px-6">
    <div className="text-5xl mb-4">{icon}</div>
    <h2 className="text-lg font-orbitron font-bold text-slate-800 mb-2">{title}</h2>
    <p className="text-slate-500 text-sm font-inter max-w-xs leading-relaxed">{description}</p>
    <div className="mt-6 px-4 py-2 rounded-xl glass-panel text-xs text-gold-dark border border-gold-glow/20">
      Coming in Phase 3
    </div>
  </div>
);

export default App;
