/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./templates/**/*.html"],
  theme: {
    extend: {
      fontFamily: {
        'sans': ['Raleway', 'sans-serif'],
        'serif': ['Playfair Display', 'serif'],
      },
      colors: {
        'premium-gold': {
          100: '#FFF7E6',
          200: '#FFE9B3',
          300: '#FFD980',
          400: '#FFC94D',
          500: '#FFB81A',
          600: '#E6A600',
          700: '#B38300',
          800: '#805E00',
          900: '#4D3800',
        },
      },
    },
  },
  plugins: [
    require('@tailwindcss/typography'),
  ],
}

