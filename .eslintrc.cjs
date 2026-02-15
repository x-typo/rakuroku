module.exports = {
  root: true,
  extends: ["expo"],
  overrides: [
    {
      files: ["jest.setup.ts", "**/*.test.ts", "**/*.test.tsx"],
      rules: {
        "@typescript-eslint/no-require-imports": "off",
      },
    },
  ],
};
