import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';

export type AppTheme = 'default' | 'night' | 'colorblind' | 'system';

interface ThemeState {
  theme: AppTheme;
  setTheme: (theme: AppTheme) => void;
}

export const useThemeStore = create<ThemeState>()(
  persist(
    (set) => ({
      theme: 'default',
      setTheme: (theme: AppTheme) => set({ theme }),
    }),
    {
      name: 'universal-theme-storage',
      storage: createJSONStorage(() => localStorage),
    }
  )
);
