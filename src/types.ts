export type VoiceState = 'idle' | 'listening' | 'processing' | 'speaking';

export interface Message {
  id: string;
  type: 'user' | 'assistant';
  content: string;
  timestamp: Date;
}

export interface VoiceContextType {
  state: VoiceState;
  transcript: string;
  isListening: boolean;
  messages: Message[];
  isProcessing: boolean;
  isSpeaking: boolean;
  startListening: () => void;
  stopListening: () => void;
  clearHistory: () => void;
  addMessage: (message: Message) => void;
}

export interface CoreVisualizerState {
  rotation: number;
  particleCount: number;
  glowIntensity: number;
  pulsing: boolean;
}
