/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["*.{html,js}"],
  darkMode: false,
  theme: {
    extend: {
      colors: {
        'off-white': '#f5f5f5',
        'gold-premium': '#DAA520',
      },
      fontFamily: {
        'montserrat': ['Montserrat', 'sans-serif'],
      },
    },
  },
  plugins: [],
}

