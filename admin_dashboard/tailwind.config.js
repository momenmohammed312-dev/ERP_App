/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          50: '#eff6ff',
          100: '#dbeafe',
          500: '#3b82f6',
          600: '#1677ff', // Mantis Blue
          700: '#0958d9',
        },
        madar: {
          gold: '#c9a84c',
          goldLight: '#e8c97a',
          navy: '#0f172a',
          slate: '#1e293b',
        }
      },
      fontFamily: {
        arabic: ['Cairo', 'Tajawal', 'system-ui', 'sans-serif'],
      }
    },
  },
  plugins: [],
}
