// required packages
// @typescript-eslint
// prettier
// eslint-config-airbnb
// eslint-config-prettier
// eslint-plugin-prettier
// eslint-plugin-react
// eslint-plugin-jsx-a11y
// eslint-plugin-import
// eslint-plugin-react-hooks

module.exports = {
  parser: '@typescript-eslint/parser',
  parserOptions: {
    sourceType: 'module',
  },
  env: {
    es6: true,
    browser: true,
  },
  extends: ['airbnb', 'plugin:prettier/recommended'],
  plugins: ['@typescript-eslint', 'react', 'jsx-a11y', 'react-hooks', 'import'],
  settings: {
    'import/extensions': ['.js', '.jsx', '.ts', '.tsx'],
    'import/resolver': {
      node: {
        extensions: ['.js', '.jsx', '.ts', '.tsx'],
      },
    },
  },
  rules: {
    'prettier/prettier': [
      'error',
      {
        printWidth: 120,
        semi: true,
        singleQuote: true,
        trailingComma: 'es5',
      },
    ],
    'react/prop-types': [0],
    'import/extensions': [
      'error',
      'always',
      {
        js: 'never',
        jsx: 'never',
        ts: 'never',
        tsx: 'never',
      },
    ],
  },
};
