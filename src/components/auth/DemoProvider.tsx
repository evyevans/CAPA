import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { GUEST_KEY } from '../../App';
import { Context, guest } from '../../hooks/useAuth';
export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const navigate = useNavigate();
  const [active, setActive] = useState(() => localStorage.getItem(GUEST_KEY) === 'true');
  const enterDemo = () => { localStorage.setItem(GUEST_KEY, 'true'); setActive(true); navigate('/dashboard'); };
  const signOut = async () => { localStorage.removeItem(GUEST_KEY); setActive(false); navigate('/login'); };
  return <Context.Provider value={{ session: active ? { user: guest } : null, user: active ? guest : null,
    loading: false, enterDemo, signOut }}>{children}</Context.Provider>;
};
