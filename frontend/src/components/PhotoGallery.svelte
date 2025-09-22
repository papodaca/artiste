<script>
  import { onMount, onDestroy } from "svelte";
  import PhotoItem from "./PhotoItem.svelte";
  import PhotoDetailsModal from "./PhotoDetailsModal.svelte";

  let photos = $state([]);
  let loading = $state(false);
  let hasMore = $state(true);
  let offset = $state(0);
  const batchSize = 20;
  let selectedPhoto = $state(null);
  let showModal = $state(false);
  let websocket = $state(null);
  let connectionStatus = $state("disconnected");

  // Fetch initial photos
  onMount(async () => {
    await loadPhotos();
    window.addEventListener("scroll", handleScroll);
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
      const response = await fetch(
        `/api/photos?offset=${offset}&limit=${batchSize}`,
      );
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
      console.error("Error loading photos:", error);
    } finally {
      loading = false;
    }
  }

  // Handle infinite scroll
  function handleScroll() {
    if (
      window.innerHeight + window.scrollY >=
      document.body.offsetHeight - 1000
    ) {
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
      const wsProtocol = window.location.protocol === "https:" ? "wss:" : "ws:";
      const wsHost = window.location.hostname;
      let wsUrl = "";
      if (
        wsHost === "localhost" ||
        wsHost === "127.0.0.1" ||
        wsHost === "[::1]"
      ) {
        wsUrl = `${wsProtocol}//${wsHost}:4568`;
      } else {
        wsUrl = `${wsProtocol}//${wsHost}/ws`;
      }

      websocket = new WebSocket(wsUrl);
      connectionStatus = "connecting";

      websocket.onopen = () => {
        console.log("WebSocket connected");
        connectionStatus = "connected";
      };

      websocket.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          handleWebSocketMessage(data);
        } catch (error) {
          console.error("Error parsing WebSocket message:", error);
        }
      };

      websocket.onclose = () => {
        console.log("WebSocket disconnected");
        connectionStatus = "disconnected";
        // Attempt to reconnect after 5 seconds
        setTimeout(() => connectWebSocket(), 5000);
      };

      websocket.onerror = (error) => {
        console.error("WebSocket error:", error);
        connectionStatus = "error";
      };
    } catch (error) {
      console.error("Failed to connect to WebSocket:", error);
      connectionStatus = "error";
    }
  }

  function handleWebSocketMessage(data) {
    console.log("Received WebSocket message:", data);

    switch (data.type) {
      case "new_photo":
        // Add new photo to the beginning of the list
        photos = [data.photo_path, ...photos];
        break;

      case "photo_updated":
        // Handle photo updates if needed
        console.log("Photo updated:", data.photo_path);
        break;

      case "pong":
        // Handle pong response
        break;

      default:
        console.log("Unknown WebSocket message type:", data.type);
    }
  }

  // Send ping to keep connection alive
  function sendPing() {
    if (websocket && websocket.readyState === WebSocket.OPEN) {
      websocket.send(JSON.stringify({ type: "ping" }));
    }
  }

  // Start ping interval
  setInterval(sendPing, 30000);
</script>

<div class="max-w-6xl mx-auto p-5">
  <!-- WebSocket connection status indicator - Upper right -->
  <div
    class="fixed top-4 right-4 flex items-center gap-2 p-2 bg-white dark:bg-gray-800 rounded-lg shadow-lg text-xs z-50"
  >
    <div
      class={`w-2 h-2 rounded-full ${
        connectionStatus === "connected"
          ? "bg-green-500"
          : connectionStatus === "connecting"
            ? "bg-yellow-500"
            : connectionStatus === "error"
              ? "bg-red-500"
              : "bg-gray-500"
      }`}
    ></div>
    <span class="text-gray-600 dark:text-gray-400">
      {connectionStatus === "connected"
        ? "Live"
        : connectionStatus === "connecting"
          ? "Connecting..."
          : connectionStatus === "error"
            ? "Connection Error"
            : "Disconnected"}
    </span>
  </div>

  <h1
    class="text-center text-gray-800 dark:text-gray-200 mb-8 text-3xl font-bold flex items-center justify-center gap-3"
  >
    <img
      src="/assets/artiste.png"
      alt="Artiste"
      class="w-12 h-12 rounded-full object-cover"
    />
    Artiste
  </h1>

  {#if photos.length === 0}
    <div class="text-center text-gray-600 dark:text-gray-400 italic mt-12">
      No photos found.
    </div>
  {:else}
    <div
      class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5 infinite-scroll-container"
    >
      {#each photos as photo}
        <PhotoItem {photo} onshowDetails={showPhotoDetails} />
      {/each}
    </div>

    {#if loading}
      <div class="text-center py-8">
        <div
          class="inline-block h-8 w-8 animate-spin rounded-full border-4 border-solid border-current border-r-transparent align-[-0.125em] motion-reduce:animate-[spin_1.5s_linear_infinite]"
          role="status"
        >
          <span
            class="!absolute !-m-px !h-px !w-px !overflow-hidden !whitespace-nowrap !border-0 !p-0 ![clip:rect(0,0,0,0)]"
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
