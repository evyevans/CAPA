import React, { useMemo } from 'react';
import { motion } from 'framer-motion';
import { VoiceState } from '../types';

interface CapaCoreProps {
  state: VoiceState;
  isSpeaking?: boolean;
}

const CapaCore: React.FC<CapaCoreProps> = ({ state }) => {
  const getStateConfig = () => {
    switch (state) {
      case 'listening':
        return {
          ringRotation: 360,
          ringDuration: 2,
          coreScale: 1.15,
          corePulse: 1.5,
          strokeColor: 'rgba(234, 179, 8, 0.6)',
          fillColor: 'rgba(234, 179, 8, 0.15)',
        };
      case 'processing':
        return {
          ringRotation: -360,
          ringDuration: 1,
          coreScale: 1.1,
          corePulse: 1,
          strokeColor: 'rgba(71, 85, 105, 0.6)',
          fillColor: 'rgba(71, 85, 105, 0.1)',
        };
      case 'speaking':
        return {
          ringRotation: 180,
          ringDuration: 3,
          coreScale: 1.2,
          corePulse: 2,
          strokeColor: 'rgba(234, 179, 8, 0.8)',
          fillColor: 'rgba(234, 179, 8, 0.2)',
        };
      default:
        return {
          ringRotation: 0,
          ringDuration: 0,
          coreScale: 1,
          corePulse: 1,
          strokeColor: 'rgba(234, 179, 8, 0.4)',
          fillColor: 'rgba(234, 179, 8, 0.08)',
        };
    }
  };

  const config = getStateConfig();
  const particles = useMemo(
    () =>
      Array.from({ length: state === 'processing' ? 30 : state === 'listening' ? 20 : 8 }).map((_, i) => ({
        id: i,
        angle: (i / 20) * Math.PI * 2,
        distance: 80 + Math.random() * 40,
      })),
    [state]
  );

  return (
    <div className="relative w-72 h-72 flex items-center justify-center">
      <svg
        viewBox="0 0 300 300"
        className="absolute inset-0 w-full h-full"
        style={{
          filter: 'drop-shadow(0 4px 12px rgba(234, 179, 8, 0.1))',
        }}
      >
        {/* Outer Ring Layer 1 */}
        <motion.g
          animate={{
            rotate: config.ringRotation,
          }}
          transition={{
            duration: config.ringDuration || 20,
            repeat: Infinity,
            ease: 'linear',
          }}
        >
          <circle
            cx="150"
            cy="150"
            r="110"
            fill="none"
            stroke={config.strokeColor}
            strokeWidth="1.5"
            strokeDasharray="10 5"
            opacity={0.5}
          />
          {Array.from({ length: 12 }).map((_, i) => (
            <line
              key={`tick-${i}`}
              x1="150"
              y1="40"
              x2="150"
              y2="48"
              stroke={config.strokeColor}
              strokeWidth="1"
              opacity={0.4}
              transform={`rotate(${(i / 12) * 360} 150 150)`}
            />
          ))}
        </motion.g>

        {/* Middle Ring Layer 2 */}
        <motion.g
          animate={{
            rotate: config.ringRotation ? -config.ringRotation * 0.8 : -360,
          }}
          transition={{
            duration: config.ringDuration ? config.ringDuration * 1.2 : 25,
            repeat: Infinity,
            ease: 'linear',
          }}
        >
          <circle
            cx="150"
            cy="150"
            r="85"
            fill="none"
            stroke={config.strokeColor}
            strokeWidth="1"
            opacity={0.35}
          />
        </motion.g>

        {/* Inner Ring Layer 3 */}
        <motion.g
          animate={{
            rotate: config.ringRotation || 360,
          }}
          transition={{
            duration: config.ringDuration ? config.ringDuration * 1.5 : 30,
            repeat: Infinity,
            ease: 'linear',
          }}
        >
          <circle
            cx="150"
            cy="150"
            r="60"
            fill="none"
            stroke="rgba(148, 163, 184, 0.3)"
            strokeWidth="0.5"
            strokeDasharray="4 2"
            opacity={0.5}
          />
        </motion.g>

        {/* Center Hexagon */}
        <motion.polygon
          points="150,105 175,120 175,150 150,165 125,150 125,120"
          fill={config.fillColor}
          stroke={config.strokeColor}
          strokeWidth="2"
          animate={{
            scale: [1, 1.02, 1],
            opacity: [0.6, 1, 0.6],
          }}
          transition={{
            scale: {
              duration: config.corePulse,
              repeat: Infinity,
              ease: 'easeInOut',
            },
            opacity: {
              duration: config.corePulse,
              repeat: Infinity,
              ease: 'easeInOut',
            },
          }}
        />

        {/* Center Glow */}
        <motion.circle
          cx="150"
          cy="150"
          r="15"
          fill="rgba(234, 179, 8, 0.4)"
          animate={{
            r: state === 'idle' ? [12, 18, 12] : [15, 22, 15],
            opacity: [0.4, 0.7, 0.4],
          }}
          transition={{
            duration: config.corePulse,
            repeat: Infinity,
            ease: 'easeInOut',
          }}
        />

        {/* Ripple Effect for Listening */}
        {state === 'listening' && (
          <>
            <motion.circle
              cx="150"
              cy="150"
              r="40"
              fill="none"
              stroke="rgba(234, 179, 8, 0.4)"
              strokeWidth="1"
              animate={{
                r: [40, 110],
                opacity: [0.6, 0],
              }}
              transition={{
                duration: 1.5,
                repeat: Infinity,
              }}
            />
            <motion.circle
              cx="150"
              cy="150"
              r="40"
              fill="none"
              stroke="rgba(234, 179, 8, 0.3)"
              strokeWidth="1"
              animate={{
                r: [40, 110],
                opacity: [0.4, 0],
              }}
              transition={{
                duration: 1.5,
                delay: 0.5,
                repeat: Infinity,
              }}
            />
          </>
        )}

        {/* Data Points */}
        {Array.from({ length: state === 'idle' ? 3 : 6 }).map((_, i) => (
          <motion.circle
            key={`datapoint-${i}`}
            cx={150 + Math.cos((i / 6) * Math.PI * 2) * 90}
            cy={150 + Math.sin((i / 6) * Math.PI * 2) * 90}
            r="2.5"
            fill="rgba(234, 179, 8, 0.6)"
            animate={{
              opacity: [0.3, 0.8, 0.3],
              scale: [0.8, 1.2, 0.8],
            }}
            transition={{
              duration: 2 + i * 0.2,
              repeat: Infinity,
              ease: 'easeInOut',
            }}
          />
        ))}

        {/* Corner Accent Markers */}
        {Array.from({ length: 4 }).map((_, i) => (
          <g key={`corner-${i}`} opacity={0.4}>
            <line
              x1={150 + Math.cos((i / 4) * Math.PI * 2 + Math.PI / 4) * 115}
              y1={150 + Math.sin((i / 4) * Math.PI * 2 + Math.PI / 4) * 115}
              x2={150 + Math.cos((i / 4) * Math.PI * 2 + Math.PI / 4) * 120}
              y2={150 + Math.sin((i / 4) * Math.PI * 2 + Math.PI / 4) * 120}
              stroke={config.strokeColor}
              strokeWidth="2"
              strokeLinecap="round"
            />
          </g>
        ))}
      </svg>

      {/* Floating Particles around core */}
      {particles.map(particle => (
        <motion.div
          key={particle.id}
          className="absolute w-1 h-1 rounded-full"
          style={{
            left: '50%',
            top: '50%',
            marginLeft: -2,
            marginTop: -2,
            background: 'rgba(234, 179, 8, 0.5)',
            boxShadow: '0 0 4px rgba(234, 179, 8, 0.3)',
          }}
          animate={{
            x: Math.cos(particle.angle) * particle.distance,
            y: Math.sin(particle.angle) * particle.distance,
            opacity: state === 'processing' ? [0.8, 0] : [0.5, 0.2],
            scale: state === 'processing' ? [1, 0.5] : [1, 0.7],
          }}
          transition={{
            duration: state === 'processing' ? 0.8 : 2.5,
            repeat: Infinity,
            ease: state === 'processing' ? 'easeIn' : 'easeInOut',
            delay: (particle.id / particles.length) * 0.5,
          }}
        />
      ))}
    </div>
  );
};

export default CapaCore;
