function copyImageUrl(relativePath) {
  return async (event) => {
    event.stopPropagation();
    try {
      const permission = await navigator.permissions.query({ name: 'clipboard-write' })
      if (permission.state !== "granted") return

      const fullUrl = window.location.origin + relativePath;
      const type = 'text/plain';
      const clipboardItemData = {
        [type]: fullUrl
      };
      const clipboardItem = new ClipboardItem(clipboardItemData);
      const button = event.target.closest('button');
      const originalHTML = button.innerHTML;
      await navigator.clipboard.write([clipboardItem]);

      button.innerHTML = `
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="w-5 h-5">
          <polyline points="20,6 9,17 4,12"></polyline>
        </svg>
      `;

      setTimeout(() => {
        button.innerHTML = originalHTML;
      }, 1500);
    } catch (error) {
      console.error('Error copying URL:', error);
    }
  }
}

function attachImageClick(button) {
  if (button.dataset.click === "true") return
  const url = button.dataset.photoPath
  button.addEventListener('click', copyImageUrl(url))
  button.dataset.click = "true"
}

function attachImageClicks() {
  document.querySelectorAll(".photo-copy").forEach(el => attachImageClick(el));
}

// WebSocket connection
let websocket = null;
let connectionStatus = 'disconnected';

function updateConnectionStatus() {
  const dot = document.getElementById('connection-status-dot');
  const text = document.getElementById('connection-status-text');

  if (connectionStatus === 'connected') {
    dot.className = 'h-2 w-2 rounded-full bg-green-500';
    text.textContent = 'Live';
  } else if (connectionStatus === 'connecting') {
    dot.className = 'h-2 w-2 rounded-full bg-yellow-500';
    text.textContent = 'Connecting...';
  } else if (connectionStatus === 'error') {
    dot.className = 'h-2 w-2 rounded-full bg-red-500';
    text.textContent = 'Connection Error';
  } else {
    dot.className = 'h-2 w-2 rounded-full bg-gray-500';
    text.textContent = 'Disconnected';
  }
}

function connectWebSocket() {
  try {
    const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsHost = window.location.hostname;
    let wsUrl = '';
    if (wsHost === 'localhost' || wsHost === '127.0.0.1' || wsHost === '[::1]') {
      wsUrl = `${wsProtocol}//${wsHost}:4568`;
    } else {
      wsUrl = `${wsProtocol}//${wsHost}/ws`;
    }

    websocket = new WebSocket(wsUrl);
    connectionStatus = 'connecting';
    updateConnectionStatus();

    websocket.onopen = () => {
      console.log('WebSocket connected');
      connectionStatus = 'connected';
      updateConnectionStatus();
    };

    websocket.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);

        if (data.type === "new_photo") {
          Turbo.renderStreamMessage(data.html);
        }
      } catch (error) {
        console.error('Error parsing WebSocket message:', error);
        showNotification('Failed to process gallery update', 'error');
      }
    };

    websocket.onclose = () => {
      console.log('WebSocket disconnected');
      connectionStatus = 'disconnected';
      updateConnectionStatus();
      // Attempt to reconnect after 5 seconds
      setTimeout(() => connectWebSocket(), 5000);
    };

    websocket.onerror = (error) => {
      console.error('WebSocket error:', error);
      connectionStatus = 'error';
      updateConnectionStatus();
    };
  } catch (error) {
    console.error('Failed to connect to WebSocket:', error);
    connectionStatus = 'error';
    updateConnectionStatus();
  }
}

// Send ping to keep connection alive
function sendPing() {
  if (websocket && websocket.readyState === WebSocket.OPEN) {
    websocket.send(JSON.stringify({ type: 'ping' }));
  }
}

// Initialize WebSocket connection
document.addEventListener('DOMContentLoaded', () => {
  connectWebSocket();
  // Start ping interval
  setInterval(sendPing, 30000);

  // Initialize infinite scroll
  initializeInfiniteScroll();
});

// Infinite scroll implementation
let isLoading = false;
let observer = null;

function initializeInfiniteScroll() {
  // Disconnect existing observer if any
  if (observer) {
    observer.disconnect();
  }

  const loadMoreTrigger = document.getElementById('load-more-trigger');

  if (!loadMoreTrigger) {
    console.log('No load-more-trigger found, infinite scroll disabled');
    return;
  }

  // Create an Intersection Observer to detect when the trigger is visible
  observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting && !isLoading) {
        loadMorePhotos();
      }
    });
  }, {
    root: null, // viewport
    rootMargin: '100px', // start loading 100px before the trigger comes into view
    threshold: 0.1
  });

  observer.observe(loadMoreTrigger);
}

async function loadMorePhotos() {
  const trigger = document.getElementById('load-more-trigger');
  if (!trigger || isLoading) return;

  isLoading = true;

  try {
    const offset = trigger.dataset.offset;
    const limit = trigger.dataset.limit;

    const response = await fetch(`/tasks?offset=${offset}&limit=${limit}`, {
      headers: {
        'Accept': 'text/vnd.turbo-stream.html'
      }
    });

    if (response.ok) {
      const streamHtml = await response.text();
      // Process the Turbo Stream response
      Turbo.renderStreamMessage(streamHtml);

      // Re-initialize the infinite scroll after a short delay to ensure DOM is updated
      setTimeout(() => {
        initializeInfiniteScroll();
      }, 100);
    } else {
      console.error('Failed to load more photos:', response.statusText);
    }
  } catch (error) {
    console.error('Error loading more photos:', error);
  } finally {
    isLoading = false;
  }
}

function closePhotoModal() {
  const modalFrame = document.querySelector('#photo-modal-frame');
  if (modalFrame) {
    // Add fade-out animation to the modal content
    const modalContent = modalFrame.querySelector('#photo-modal');
    if (modalContent) {
      modalContent.classList.add('fade-out');

      // Wait for the animation to complete before removing the modal
      setTimeout(() => {
        modalFrame.removeAttribute("src");
        modalContent.remove();
        // Remove detail query parameter from URL
        removeDetailQueryParam();
      }, 300); // Match the duration of the fade-out animation
    } else {
      // Fallback if modal content is not found
      modalFrame.removeAttribute("src");
      modalFrame.childNodes.forEach(el => el.remove())
      // Remove detail query parameter from URL
      removeDetailQueryParam();
    }
  }
}

function removeDetailQueryParam() {
  const url = new URL(window.location);
  url.searchParams.delete('detail');
  const newUrl = url.pathname + url.search;
  window.history.replaceState({}, '', newUrl);
}

// Add ESC key listener to close modal
document.addEventListener('keydown', function (event) {
  if (event.key === 'Escape') {
    closePhotoModal();
  }
});