import React, { useMemo } from 'react';
import { motion } from 'framer-motion';

interface WaveformVisualizerProps {
  isActive: boolean;
}

const WaveformVisualizer: React.FC<WaveformVisualizerProps> = ({ isActive }) => {
  const bars = useMemo(() => Array.from({ length: 12 }).map((_, i) => ({ id: i })), []);

  if (!isActive) return null;

  return (
    <div className="flex items-center justify-center gap-1 h-16">
      {bars.map(bar => (
        <motion.div
          key={bar.id}
          className="w-1 bg-gradient-to-t from-cyan-glow to-cyan-light rounded-full"
          style={{
            minHeight: '8px',
            boxShadow: '0 0 6px rgba(6, 182, 212, 0.3)',
          }}
          animate={{
            height: isActive ? ['8px', '32px', '24px', '16px'] : '8px',
          }}
          transition={{
            duration: 0.6,
            repeat: Infinity,
            delay: bar.id * 0.05,
            ease: 'easeInOut',
          }}
        />
      ))}
    </div>
  );
};

export default WaveformVisualizer;
