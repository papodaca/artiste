<script>
  import { createEventDispatcher } from "svelte";

  export let photo;

  const dispatch = createEventDispatcher();

  function showDetails() {
    dispatch("showDetails", photo);
  }

  async function copyImageUrl(event, relativePath) {
    event.stopPropagation();

    try {
      // Get the full URL (handles different deployment paths)
      const fullUrl = window.location.origin + relativePath;

      const type = "text/plain";
      const clipboardItemData = {
        [type]: fullUrl,
      };
      const clipboardItem = new ClipboardItem(clipboardItemData);
      await navigator.clipboard.write([clipboardItem]);

      // Show visual feedback
      const button = event.target.closest("button");
      const originalHTML = button.innerHTML;

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
      console.error("Error copying URL:", error);
    }
  }

  function getFilename(path) {
    return path.split("/").pop();
  }
</script>

<div
  class="bg-white dark:bg-gray-800 rounded-lg shadow-lg overflow-hidden transition-transform duration-200 hover:-translate-y-1 hover:shadow-xl fade-in relative"
>
  <div class="block no-underline cursor-pointer" on:click={showDetails}>
    <img
      src="/photo/{encodeURIComponent(photo)}"
      alt={getFilename(photo)}
      class="w-full h-64 object-cover block"
    />
    <div class="p-4">
      <div class="font-bold text-gray-800 dark:text-gray-200 mb-1 break-words">
        {getFilename(photo)}
      </div>
      <div class="text-sm text-gray-600 dark:text-gray-400 break-words">
        {photo}
      </div>
    </div>
  </div>
  <button
    type="button"
    class="absolute top-2 right-2 p-2 rounded-full bg-white/80 dark:bg-gray-800/80 backdrop-blur-sm hover:bg-white dark:hover:bg-gray-800 text-gray-800 dark:text-gray-200 shadow-md hover:shadow-lg transition-all duration-200 z-10"
    aria-label="Copy image URL to clipboard"
    on:click={(event) =>
      copyImageUrl(event, "/photo/" + encodeURIComponent(photo))}
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
      class="w-5 h-5"
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
