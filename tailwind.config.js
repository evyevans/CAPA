/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      fontFamily: {
        orbitron: ['Orbitron', 'monospace'],
        inter: ['Inter', 'sans-serif'],
      },
      colors: {
        bg: {
          primary: 'var(--color-bg-primary)',
          surface: 'var(--color-bg-surface)',
          elevated: 'var(--color-bg-elevated)',
          dark: 'var(--color-bg-dark)',
        },
        accent: {
          DEFAULT: 'var(--color-accent)',
          hover: 'var(--color-accent-hover)',
          tertiary: 'var(--color-accent-tertiary)',
        },
        text: {
          primary: 'var(--color-text-primary)',
          secondary: 'var(--color-text-secondary)',
          tertiary: 'var(--color-text-tertiary)',
          'on-accent': 'var(--color-text-on-accent)',
        },
        border: 'var(--color-border)',
        cyan: {
          glow: '#06B6D4',
          light: '#67E8F9',
          dark: '#0891B2',
        },
        gold: {
          glow: '#EAB308',
          light: '#FDE047',
          dark: '#A16207',
          premium: '#D4AF37',
        },
      },
      backgroundImage: {
        'light-gradient': 'radial-gradient(circle at center, #FFFFFF 0%, #FFFDF5 100%)',
        'ambient-glow': 'radial-gradient(circle at center, rgba(234, 179, 8, 0.08) 0%, rgba(234, 179, 8, 0.04) 30%, transparent 70%)',
      },
      boxShadow: {
        'sm': 'var(--shadow-sm)',
        'md': 'var(--shadow-md)',
        'lg': 'var(--shadow-lg)',
        'glass': '0 8px 32px 0 rgba(161, 98, 7, 0.05)',
        'glass-lg': '0 12px 48px 0 rgba(161, 98, 7, 0.08)',
        'soft': '0 2px 8px rgba(0, 0, 0, 0.02), 0 4px 16px rgba(0, 0, 0, 0.03)',
        'gold-subtle': '0 0 40px rgba(234, 179, 8, 0.12)',
        'gold-glow': '0 0 20px rgba(234, 179, 8, 0.25), 0 0 40px rgba(234, 179, 8, 0.1)',
      },
      keyframes: {
        'breathing-pulse': {
          '0%, 100%': { opacity: '0.6', transform: 'scale(1)' },
          '50%': { opacity: '1', transform: 'scale(1.05)' },
        },
        'soft-pulse': {
          '0%, 100%': { opacity: '0.8', transform: 'scale(1)' },
          '50%': { opacity: '1', transform: 'scale(1.02)' },
        },
        'hex-rotate': {
          '0%': { transform: 'rotate(0deg)' },
          '100%': { transform: 'rotate(360deg)' },
        },
        'hex-rotate-reverse': {
          '0%': { transform: 'rotate(360deg)' },
          '100%': { transform: 'rotate(0deg)' },
        },
        'particle-float': {
          '0%': { opacity: '0', transform: 'translateY(20px)' },
          '10%': { opacity: '0.6' },
          '90%': { opacity: '0.6' },
          '100%': { opacity: '0', transform: 'translateY(-100px)' },
        },
        'ripple-expand': {
          '0%': { r: '0', opacity: '0.8' },
          '100%': { r: '120', opacity: '0' },
        },
      },
      animation: {
        'breathing-pulse': 'breathing-pulse 3s ease-in-out infinite',
        'soft-pulse': 'soft-pulse 2s ease-in-out infinite',
        'hex-rotate': 'hex-rotate 20s linear infinite',
        'hex-rotate-reverse': 'hex-rotate-reverse 25s linear infinite',
        'particle-float': 'particle-float 4s ease-out forwards',
        'ripple-expand': 'ripple-expand 1.5s ease-out infinite',
      },
    },
  },
  plugins: [],
};
