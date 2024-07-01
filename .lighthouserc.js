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
            'categories:performance': ['error', {minScore: 0.95}],
            'categories:accessibility': ['error', {minScore: 0.95}],
            'categories:best-practices': ['error', {minScore: 0.95}],
            'categories:seo': ['error', {minScore: 0.95}],

            // Ignore checks which have no benefit for me right now
            'first-contentful-paint': ['error', {minScore: 0.8}],
            'render-blocking-resources': 'off',
            'uses-long-cache-ttl': 'off',
          },
        },
        {
          matchingUrlPattern: "^http://[^/]+/blog/.*/",
          preset: 'lighthouse:no-pwa',
          assertions: {
            'categories:performance': ['error', {minScore: 0.95}],
            'categories:accessibility': ['error', {minScore: 0.95}],
            'categories:best-practices': ['error', {minScore: 0.95}],
            'categories:seo': ['error', {minScore: 0.95}],

            // Ignore checks which have no benefit for me right now
            'first-contentful-paint': ['error', {minScore: 0.8}],
            'render-blocking-resources': 'off',
            'uses-long-cache-ttl': 'off',

            // Also ignore syntax highlighting contrast checks
            "color-contrast": "off"
          },
        }
      ],
    },
    upload: {
      target: 'temporary-public-storage',
    },
  },
};
