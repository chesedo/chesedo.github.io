module.exports = {
  ci: {
    collect: {
      staticDistDir: './public',
    },
    assert: {
      preset: 'lighthouse:no-pwa',
      assertions: {
        'categories:performance': ['error', {minScore: 0.9}],
        'categories:accessibility': ['error', {minScore: 0.9}],
        'categories:best-practices': ['error', {minScore: 0.9}],
        'categories:seo': ['error', {minScore: 0.9}],

        // Ignore checks which have no benefit for me right now
        'first-contentful-paint': ['error', {minScore: 0.8}],
        'render-blocking-resources': 'off',
        'uses-long-cache-ttl': 'off',
      },
    },
    upload: {
      target: 'temporary-public-storage',
    },
  },
};
