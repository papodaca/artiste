<script>
  const { photo, onshowDetails } = $props();

  function showDetails() {
    onshowDetails?.(photo);
  }

  async function copyImageUrl(event, relativePath) {
    event.stopPropagation();

    try {
      // Get the full URL (handles different deployment paths)
      const fullUrl = window.location.origin + relativePath;
      const type = 'text/plain';
      const clipboardItemData = {
        [type]: fullUrl
      };
      const clipboardItem = new ClipboardItem(clipboardItemData);
      const button = event.target.closest('button');
      const originalHTML = button.innerHTML;
      await navigator.clipboard.write([clipboardItem]);

      // Show visual feedback

      // Show checkmark icon
      button.innerHTML = `
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="w-5 h-5">
          <polyline points="20,6 9,17 4,12"></polyline>
        </svg>
      `;

      // Reset after 1.5 seconds
      setTimeout(() => {
        button.innerHTML = originalHTML;
      }, 1500);
    } catch (error) {
      console.error('Error copying URL:', error);
    }
  }

  function getFilename(path) {
    return path.split('/').pop();
  }

  function isVideo(path) {
    return path.toLowerCase().endsWith('.mp4');
  }
</script>

<div
  class="fade-in relative overflow-hidden rounded-lg bg-white shadow-lg transition-transform duration-200 hover:-translate-y-1 hover:shadow-xl dark:bg-gray-800"
>
  <div class="block cursor-pointer no-underline" onclick={showDetails}>
    {#if isVideo(photo)}
      <video src="/photos/{photo}" class="block h-64 w-full object-cover" autoplay muted loop />
    {:else}
      <img src="/photos/{photo}" alt={getFilename(photo)} class="block h-64 w-full object-cover" />
    {/if}
    <div class="p-4">
      <div class="mb-1 font-bold break-words text-gray-800 dark:text-gray-200">
        {getFilename(photo)}
      </div>
      <div class="text-sm break-words text-gray-600 dark:text-gray-400">
        {photo}
      </div>
    </div>
  </div>
  <button
    type="button"
    class="absolute top-2 right-2 z-10 rounded-full bg-white/80 p-2 text-gray-800 shadow-md backdrop-blur-sm transition-all duration-200 hover:bg-white hover:shadow-lg dark:bg-gray-800/80 dark:text-gray-200 dark:hover:bg-gray-800"
    aria-label="Copy image URL to clipboard"
    onclick={(event) => copyImageUrl(event, `/photos/${photo}`)}
  >
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class="h-5 w-5"
    >
      <rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect>
      <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>
    </svg>
  </button>
</div>

<style>
  @keyframes fadeInUp {
    from {
      opacity: 0;
      transform: translateY(20px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  .fade-in {
    animation: fadeInUp 0.5s ease-out forwards;
  }
</style>
