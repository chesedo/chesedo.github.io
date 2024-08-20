module.exports = {
  ci: {
    collect: {
      staticDistDir: './public',
    },
    assert: {
      assertMatrix: [
        {
          matchingUrlPattern: "^(?!http://[^/]+/blog/.*/)",
          preset: 'lighthouse:no-pwa',
          assertions: {
            'categories:performance': ['error', {minScore: 0.75}],
            'categories:accessibility': ['error', {minScore: 0.95}],
            'categories:best-practices': ['error', {minScore: 0.95}],
            'categories:seo': ['error', {minScore: 0.95}],

            // Ignore checks which have no benefit for me right now
            'first-contentful-paint': ['error', {minScore: 0.8}],
            'render-blocking-resources': 'off',
            'uses-long-cache-ttl': 'off',
            'offscreen-images': 'off',
            'mainthread-work-breakdown': 'warn',
            'modern-image-formats': 'warn',
          },
        },
        {
          matchingUrlPattern: "^http://[^/]+/blog/.*/",
          preset: 'lighthouse:no-pwa',
          assertions: {
            'categories:performance': ['error', {minScore: 0.92}],
            'categories:accessibility': ['error', {minScore: 0.93}],
            'categories:best-practices': ['error', {minScore: 0.95}],
            'categories:seo': ['error', {minScore: 0.95}],

            // Ignore checks which have no benefit for me right now
            'first-contentful-paint': ['error', {minScore: 0.7}],
            'render-blocking-resources': 'off',
            'uses-long-cache-ttl': 'off',
            'dom-size': 'warn',

            // Also ignore syntax highlighting contrast checks
            "color-contrast": "off",
          },
        }
      ],
    },
    upload: {
      target: 'temporary-public-storage',
    },
  },
};
