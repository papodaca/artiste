# Frontend Testing

This document explains how to run and maintain the frontend tests for the Artiste photo gallery application.

## Test Framework

We use **Vitest** as our test runner with **jsdom** for DOM testing. The tests are focused on unit testing the utility functions and logic within our Svelte components.

## Running Tests

### Run all tests once
```bash
yarn test:run
```

### Run tests in watch mode
```bash
yarn test
```

### Run tests with UI interface
```bash
yarn test:ui
```

## Linting

We use ESLint with Standard.js configuration for code formatting and linting.

### Run linter
```bash
yarn lint
```

### Auto-fix linting issues
```bash
yarn lint:fix
```

The linting is configured to:
- Enforce consistent code formatting
- Use semicolons
- Use single quotes
- Maintain proper indentation
- Follow Standard.js style guidelines

## Test Structure

### Test Files
- `src/components/PhotoItem.test.js` - Tests for PhotoItem component utilities
- `src/components/PhotoDetailsModal.test.js` - Tests for PhotoDetailsModal component utilities  
- `src/components/PhotoGallery.test.js` - Tests for PhotoGallery component utilities

### Test Setup
- `src/test/setup.js` - Global test configuration and mocks
- `vitest.config.js` - Vitest configuration

## What We Test

Since we're using Svelte 5, we focus on testing the pure JavaScript utility functions and logic rather than full component rendering. This approach avoids the complexity of Svelte 5's lifecycle functions in test environments.

### PhotoItem Tests
- Filename extraction from paths
- Video file detection
- URL construction for clipboard functionality
- Error handling for clipboard operations

### PhotoDetailsModal Tests
- Status class mapping
- Date formatting utilities
- Processing time formatting
- JSON formatting
- HTML escaping for security
- Video file detection

### PhotoGallery Tests
- WebSocket URL construction
- Scroll detection logic
- WebSocket message handling
- API URL construction
- Connection status mapping

## Mocks and Fixtures

The test setup includes mocks for:
- `fetch` API calls
- `WebSocket` connections
- `navigator.clipboard` API
- `window.location` and scroll properties
- Date formatting functions from `date-fns`

## Adding New Tests

When adding new utility functions to components, create corresponding tests in the appropriate test file. Follow the existing pattern:

1. Group related tests in `describe` blocks
2. Use descriptive test names with `it`
3. Test both success and error cases
4. Mock external dependencies
5. Use `expect` with appropriate matchers

## Best Practices

- Keep tests focused on single units of functionality
- Use descriptive test names that explain what is being tested
- Mock external dependencies to isolate the code under test
- Test edge cases and error conditions
- Keep test files organized alongside the components they test

## Troubleshooting

If tests fail:
1. Check that all mocks are properly set up in `src/test/setup.js`
2. Verify that the test logic matches the actual component implementation
3. Ensure all dependencies are installed (`yarn install`)
4. Check for any changes in component APIs that might need test updates