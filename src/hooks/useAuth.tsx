// Local demo navigation only. No accounts, credentials or subscription checks.
import { createContext, useContext } from 'react';
export const guest = { id: 'showcase-guest', email: 'Visual demo', user_metadata: { full_name: 'Guest User' } };
interface DemoContext {
  session: { user: typeof guest } | null;
  user: typeof guest | null;
  loading: boolean;
  enterDemo: () => void;
  signOut: () => Promise<void>;
}
export const Context = createContext<DemoContext | undefined>(undefined);
export const useAuth = () => {
  const value = useContext(Context);
  if (!value) throw new Error('Demo context missing');
  return value;
};
