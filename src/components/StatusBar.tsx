import React, { useState, useEffect } from 'react';
import { motion } from 'framer-motion';

const StatusBar: React.FC = () => {
  const [time, setTime] = useState(new Date());
  const [date, setDate] = useState(new Date());

  useEffect(() => {
    const interval = setInterval(() => {
      setTime(new Date());
      setDate(new Date());
    }, 1000);
    return () => clearInterval(interval);
  }, []);

  const formattedTime = time.toLocaleTimeString('en-US', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  });

  const formattedDate = date.toLocaleDateString('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  });

  return (
    <div className="absolute top-0 left-0 right-0 h-16 border-b border-slate-200/60 bg-white/40 backdrop-blur-sm flex items-center justify-between px-8 z-40">
      {/* Left Section - Date & Time */}
      <motion.div
        initial={{ opacity: 0, x: -20 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ duration: 0.5 }}
        className="flex flex-col font-orbitron"
      >
        <span className="text-slate-700 font-medium tracking-wider text-sm">{formattedTime}</span>
        <span className="text-slate-500 text-xs tracking-wide font-normal">{formattedDate}</span>
      </motion.div>

      {/* Center Section - System Status Badge */}
      <motion.div
        initial={{ opacity: 0, scale: 0.9 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ duration: 0.5, delay: 0.2 }}
        className="flex items-center gap-2 px-4 py-2 bg-amber-50 rounded-full border border-amber-100"
      >
        <motion.div
          className="w-2 h-2 rounded-full bg-gold-glow"
          animate={{ opacity: [0.6, 1, 0.6] }}
          transition={{ duration: 2, repeat: Infinity }}
        />
        <span className="text-amber-700 font-orbitron text-xs tracking-wider uppercase font-medium">
          System Online
        </span>
      </motion.div>

      {/* Right Section - Signal Strength */}
      <motion.div
        initial={{ opacity: 0, x: 20 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ duration: 0.5 }}
        className="flex gap-1 items-end"
      >
        {[1, 2, 3, 4].map((bar, index) => (
          <motion.div
            key={bar}
            className="w-1 bg-gold-glow rounded-sm"
            style={{ height: `${(bar / 4) * 14}px` }}
            animate={{ opacity: [0.4, 0.8] }}
            transition={{
              duration: 0.5,
              delay: index * 0.1,
              repeat: Infinity,
              repeatType: 'reverse',
            }}
          />
        ))}
      </motion.div>
    </div>
  );
};

export default StatusBar;
