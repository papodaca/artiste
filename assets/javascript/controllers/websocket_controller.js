import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["statusDot", "statusText"];
  static values = {
    status: { type: String, default: "disconnected" },
    wsUrl: String
  };

  connect() {
    this.websocket = null;
    this.pingInterval = null;
    this.connectWebSocket();
  }

  disconnect() {
    if (this.websocket) {
      this.websocket.close();
    }
    if (this.pingInterval) {
      clearInterval(this.pingInterval);
    }
  }

  connectWebSocket() {
    try {
      const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const wsHost = window.location.hostname;
      let wsUrl = '';

      if (wsHost === 'localhost' || wsHost === '127.0.0.1' || wsHost === '[::1]') {
        wsUrl = `${wsProtocol}//${wsHost}:4568`;
      } else {
        wsUrl = `${wsProtocol}//${wsHost}/ws`;
      }

      this.websocket = new WebSocket(wsUrl);
      this.statusValue = 'connecting';
      this.updateConnectionStatus();

      this.websocket.onopen = () => {
        console.log('WebSocket connected');
        this.statusValue = 'connected';
        this.updateConnectionStatus();
        this.startPingInterval();
      };

      this.websocket.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);

          if (data.type === "new_photo") {
            Turbo.renderStreamMessage(data.html);
          }
        } catch (error) {
          console.error('Error parsing WebSocket message:', error);
          this.showNotification('Failed to process gallery update', 'error');
        }
      };

      this.websocket.onclose = () => {
        console.log('WebSocket disconnected');
        this.statusValue = 'disconnected';
        this.updateConnectionStatus();
        this.stopPingInterval();
        // Attempt to reconnect after 5 seconds
        setTimeout(() => this.connectWebSocket(), 5000);
      };

      this.websocket.onerror = (error) => {
        console.error('WebSocket error:', error);
        this.statusValue = 'error';
        this.updateConnectionStatus();
      };
    } catch (error) {
      console.error('Failed to connect to WebSocket:', error);
      this.statusValue = 'error';
      this.updateConnectionStatus();
    }
  }

  startPingInterval() {
    this.pingInterval = setInterval(() => {
      if (this.websocket && this.websocket.readyState === WebSocket.OPEN) {
        this.websocket.send(JSON.stringify({ type: 'ping' }));
      }
    }, 30000);
  }

  stopPingInterval() {
    if (this.pingInterval) {
      clearInterval(this.pingInterval);
      this.pingInterval = null;
    }
  }

  statusValueChanged() {
    this.updateConnectionStatus();
  }

  updateConnectionStatus() {
    if (!this.hasStatusDotTarget || !this.hasStatusTextTarget) return;

    if (this.statusValue === 'connected') {
      this.statusDotTarget.className = 'h-2 w-2 rounded-full bg-green-500';
      this.statusTextTarget.textContent = 'Live';
    } else if (this.statusValue === 'connecting') {
      this.statusDotTarget.className = 'h-2 w-2 rounded-full bg-yellow-500';
      this.statusTextTarget.textContent = 'Connecting...';
    } else if (this.statusValue === 'error') {
      this.statusDotTarget.className = 'h-2 w-2 rounded-full bg-red-500';
      this.statusTextTarget.textContent = 'Connection Error';
    } else {
      this.statusDotTarget.className = 'h-2 w-2 rounded-full bg-gray-500';
      this.statusTextTarget.textContent = 'Disconnected';
    }
  }

  showNotification(message, type) {
    // This would need to be implemented or imported
    console.log(`${type}: ${message}`);
  }
}