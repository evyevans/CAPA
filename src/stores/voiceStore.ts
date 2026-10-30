/**
 * voiceStore.ts
 * Global Zustand store for CAPA voice state.
 *
 * Lifted here so AICore (mounted in DashboardLayout) can react to
 * the isSpeaking/voiceState changes that originate in useVoiceAssistant
 * (mounted in CommandCenter), without ever unmounting the Canvas.
 */
import { create } from 'zustand';
import { VoiceState } from '../types';

interface VoiceStore {
  voiceState: VoiceState;
  isSpeaking: boolean;
  setVoiceState: (s: VoiceState) => void;
  setIsSpeaking: (v: boolean) => void;
}

export const useVoiceStore = create<VoiceStore>((set) => ({
  voiceState: 'idle',
  isSpeaking: false,
  setVoiceState: (s) => set({ voiceState: s }),
  setIsSpeaking: (v) => set({ isSpeaking: v }),
}));
