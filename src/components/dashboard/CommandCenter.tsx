import React from 'react';
import { motion } from 'framer-motion';
import { useAuth } from '../../hooks/useAuth';
import { useVoiceAssistant } from '../../hooks/useVoiceAssistant';
import VoiceInterface from '../VoiceInterface';
import WaveformVisualizer from '../WaveformVisualizer';
import MessageHistory from '../MessageHistory';


const CommandCenter: React.FC = () => {
  const { user } = useAuth();
  const { state, messages, isSpeaking, handleUserInput } = useVoiceAssistant();

  const firstName = user?.email?.split('@')[0]?.split('.')[0] || 'Evy';

  return (
    <div className="flex flex-col items-center px-4 py-6 min-h-full">

      {/* Greeting */}
      <motion.div
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="text-center mb-12 mt-8"
      >
        <h1 className="text-4xl md:text-5xl text-text-primary font-inter font-light tracking-tight mb-3">
          Hello, <span className="font-orbitron font-bold text-gold-dark text-glow-gold capitalize">{firstName}</span>
        </h1>
        <p className="text-text-secondary text-sm md:text-base font-inter">
          Explore CAPA’s earlier interface with a simulated exchange.
        </p>
      </motion.div>

      {/* CAPA Core orb — Spacer for Global WebGL Core */}
      <motion.div
        initial={{ scale: 0, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ duration: 0.6, delay: 0.2 }}
        className="mb-6 w-[280px] h-[280px] md:w-[380px] md:h-[380px] relative shrink-0 pointer-events-none"
      />

      {/* Waveform when speaking */}
      {isSpeaking && (
        <motion.div
          initial={{ opacity: 0, y: -8 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0 }}
          className="mb-4"
        >
          <WaveformVisualizer isActive={isSpeaking} />
        </motion.div>
      )}

      {/* Voice Interface */}
      <motion.div
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5, delay: 0.4 }}
        className="mb-6"
      >
        <VoiceInterface state={state} onSample={() => { void handleUserInput("Demo: summarize my sample tasks"); }} />
      </motion.div>

      {/* Message history */}
      {messages.length > 0 && (
        <div className="w-full max-w-sm">
          <MessageHistory messages={messages} />
        </div>
      )}
    </div>
  );
};

export default CommandCenter;
