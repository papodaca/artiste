<script>
  import { onMount, onDestroy } from 'svelte';
  import PhotoItem from './PhotoItem.svelte';
  import PhotoDetailsModal from './PhotoDetailsModal.svelte';

  let photos = $state([]);
  let loading = $state(false);
  let hasMore = $state(true);
  let offset = $state(0);
  let selectedPhoto = $state(null);
  let showModal = $state(false);
  let websocket = $state(null);
  let connectionStatus = $state('disconnected');
  const batchSize = 20;
  const statusText = $derived.by(() => {
    if (connectionStatus === 'connected') return 'Live';
    if (connectionStatus === 'connecting') return 'Connecting...';
    if (connectionStatus === 'error') return 'Connection Error';
    return 'Disconnected';
  });
  const statusClass = $derived.by(() => {
    if (connectionStatus === 'connected') return 'bg-green-500';
    if (connectionStatus === 'connecting') return 'bg-yellow-500';
    if (connectionStatus === 'error') return 'bg-red-500';
    return 'bg-gray-500';
  });

  // Fetch initial photos
  onMount(async () => {
    await loadPhotos();
    window.addEventListener('scroll', handleScroll);
    // Check if we need to load more immediately
    setTimeout(() => handleScroll(), 100);

    // Connect to WebSocket server
    connectWebSocket();
  });

  onDestroy(() => {
    if (websocket) {
      websocket.close();
    }
  });

  // Load photos from API
  async function loadPhotos() {
    if (loading || !hasMore) return;

    loading = true;
    try {
      const response = await fetch(`/api/photos?offset=${offset}&limit=${batchSize}`);
      const data = await response.json();

      if (data.photos.length > 0) {
        photos = [...photos, ...data.photos];
        offset += data.photos.length;

        // If we got fewer photos than requested, we've reached the end
        if (data.photos.length < batchSize) {
          hasMore = false;
        }
      } else {
        hasMore = false;
      }
    } catch (error) {
      console.error('Error loading photos:', error);
    } finally {
      loading = false;
    }
  }

  // Handle infinite scroll
  function handleScroll() {
    if (window.innerHeight + window.scrollY >= document.body.offsetHeight - 1000) {
      loadPhotos();
    }
  }

  // Show photo details in modal
  function showPhotoDetails(photo) {
    selectedPhoto = photo;
    showModal = true;
  }

  // Close modal
  function closeModal() {
    showModal = false;
    selectedPhoto = null;
  }

  // WebSocket connection
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

      websocket.onopen = () => {
        console.log('WebSocket connected');
        connectionStatus = 'connected';
      };

      websocket.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          handleWebSocketMessage(data);
        } catch (error) {
          console.error('Error parsing WebSocket message:', error);
        }
      };

      websocket.onclose = () => {
        console.log('WebSocket disconnected');
        connectionStatus = 'disconnected';
        // Attempt to reconnect after 5 seconds
        setTimeout(() => connectWebSocket(), 5000);
      };

      websocket.onerror = (error) => {
        console.error('WebSocket error:', error);
        connectionStatus = 'error';
      };
    } catch (error) {
      console.error('Failed to connect to WebSocket:', error);
      connectionStatus = 'error';
    }
  }

  function handleWebSocketMessage(data) {
    console.log('Received WebSocket message:', data);

    switch (data.type) {
      case 'new_photo':
        // Add new photo to the beginning of the list
        photos = [data.photo_path, ...photos];
        break;

      case 'photo_updated':
        // Handle photo updates if needed
        console.log('Photo updated:', data.photo_path);
        break;

      case 'pong':
        // Handle pong response
        break;

      default:
        console.log('Unknown WebSocket message type:', data.type);
    }
  }

  // Send ping to keep connection alive
  function sendPing() {
    if (websocket && websocket.readyState === WebSocket.OPEN) {
      websocket.send(JSON.stringify({ type: 'ping' }));
    }
  }

  // Start ping interval
  setInterval(sendPing, 30000);
</script>

<div class="mx-auto max-w-6xl p-5">
  <!-- WebSocket connection status indicator - Upper right -->
  <div
    class="fixed top-4 right-4 z-50 flex items-center gap-2 rounded-lg bg-white p-2 text-xs shadow-lg dark:bg-gray-800"
  >
    <div class={`h-2 w-2 rounded-full ${statusClass}`}></div>
    <span class="text-gray-600 dark:text-gray-400">
      {statusText}
    </span>
  </div>

  <h1
    class="mb-8 flex items-center justify-center gap-3 text-center text-3xl font-bold text-gray-800 dark:text-gray-200"
  >
    <img src="/assets/artiste.png" alt="Artiste" class="h-12 w-12 rounded-full object-cover" />
    Artiste
  </h1>

  {#if photos.length === 0}
    <div class="mt-12 text-center text-gray-600 italic dark:text-gray-400">No photos found.</div>
  {:else}
    <div
      class="infinite-scroll-container grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
    >
      {#each photos as photo (photo)}
        <PhotoItem {photo} onshowDetails={showPhotoDetails} />
      {/each}
    </div>

    {#if loading}
      <div class="py-8 text-center">
        <div
          class="inline-block h-8 w-8 animate-spin rounded-full border-4 border-solid border-current border-r-transparent align-[-0.125em] motion-reduce:animate-[spin_1.5s_linear_infinite]"
          role="status"
        >
          <span
            class="!absolute !-m-px !h-px !w-px !overflow-hidden !border-0 !p-0 !whitespace-nowrap ![clip:rect(0,0,0,0)]"
            >Loading...</span
          >
        </div>
      </div>
    {/if}
  {/if}
</div>

{#if showModal}
  <PhotoDetailsModal {selectedPhoto} onclose={closeModal} />
{/if}

<style>
  .infinite-scroll-container {
    padding-bottom: 200px;
  }
</style>
