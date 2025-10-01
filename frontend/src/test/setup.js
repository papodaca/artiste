import '@testing-library/jest-dom';
import { vi } from 'vitest';

// Mock WebSocket for testing
global.WebSocket = class MockWebSocket {
  constructor(url) {
    this.url = url;
    this.readyState = 0; // CONNECTING
    this.onopen = null;
    this.onmessage = null;
    this.onclose = null;
    this.onerror = null;
    this.send = vi.fn();
    this.close = vi.fn();
    this.addEventListener = vi.fn();
    this.removeEventListener = vi.fn();

    // Simulate connection after a short delay
    setTimeout(() => {
      this.readyState = 1; // OPEN
      this.onopen?.();
    }, 10);
  }

  static get CONNECTING() {
    return 0;
  }

  static get OPEN() {
    return 1;
  }

  static get CLOSING() {
    return 2;
  }

  static get CLOSED() {
    return 3;
  }
};

// Mock fetch for API calls
global.fetch = vi.fn();

// Mock clipboard API
Object.assign(navigator, {
  clipboard: {
    write: vi.fn().mockResolvedValue(),
    writeText: vi.fn().mockResolvedValue()
  }
});

// Mock window.location
Object.defineProperty(window, 'location', {
  value: {
    origin: 'http://localhost:5173',
    hostname: 'localhost',
    protocol: 'http:'
  },
  writable: true
});

// Mock window.scrollY and window.innerHeight
Object.defineProperty(window, 'scrollY', {
  value: 0,
  writable: true
});

Object.defineProperty(window, 'innerHeight', {
  value: 1024,
  writable: true
});

Object.defineProperty(document.body, 'offsetHeight', {
  value: 2000,
  writable: true
});
