<script>
  import { onMount } from "svelte";
  import PhotoItem from "./PhotoItem.svelte";
  import PhotoDetailsModal from "./PhotoDetailsModal.svelte";

  let photos = [];
  let loading = false;
  let hasMore = true;
  let offset = 0;
  const batchSize = 20;
  let selectedPhoto = null;
  let showModal = false;

  // Fetch initial photos
  onMount(async () => {
    await loadPhotos();
    window.addEventListener("scroll", handleScroll);
    // Check if we need to load more immediately
    setTimeout(() => handleScroll(), 100);
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
  function showPhotoDetails(event) {
    selectedPhoto = event.detail;
    showModal = true;
  }

  // Close modal
  function closeModal() {
    showModal = false;
    selectedPhoto = null;
  }
</script>

<div class="max-w-6xl mx-auto p-5">
  <h1
    class="text-center text-gray-800 dark:text-gray-200 mb-8 text-3xl font-bold flex items-center justify-center gap-3"
  >
    Photo Gallery
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
        <PhotoItem {photo} on:showDetails={showPhotoDetails} />
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
  <PhotoDetailsModal {selectedPhoto} on:close={closeModal} />
{/if}

<style>
  .infinite-scroll-container {
    padding-bottom: 200px;
  }
</style>
