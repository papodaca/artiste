<script>
  import { createEventDispatcher, onMount } from "svelte";

  export let selectedPhoto;

  const dispatch = createEventDispatcher();
  let photoDetails = null;
  let loading = false;
  let error = null;

  onMount(async () => {
    if (selectedPhoto) {
      await fetchPhotoDetails();
    }
  });

  async function fetchPhotoDetails() {
    loading = true;
    error = null;

    try {
      const response = await fetch(
        `/api/photo-details/${encodeURIComponent(selectedPhoto)}`,
      );
      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.error || "Failed to fetch photo details");
      }

      photoDetails = data;
    } catch (err) {
      console.error("Error loading photo details:", err);
      error = err.message;
    } finally {
      loading = false;
    }
  }

  function close() {
    dispatch("close");
  }

  function getStatusClass(status) {
    switch (status) {
      case "completed":
        return "bg-status-completed-bg text-status-completed-text";
      case "processing":
        return "bg-status-processing-bg text-status-processing-text";
      case "failed":
        return "bg-status-failed-bg text-status-failed-text";
      default:
        return "bg-status-pending-bg text-status-pending-text";
    }
  }

  function formatDate(dateString) {
    return dateString || "N/A";
  }

  function formatJson(obj) {
    if (!obj || Object.keys(obj).length === 0) return "";
    return JSON.stringify(obj, null, 2);
  }

  function escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }
</script>

<div class="fixed inset-0 z-50">
  <div
    class="absolute inset-0 bg-black/50 backdrop-blur-sm"
    aria-hidden="true"
    on:click={close}
  ></div>
  <div class="fixed inset-0 overflow-y-auto">
    <div class="flex min-h-full items-center justify-center p-4">
      <div
        class="bg-white dark:bg-gray-800 rounded-lg shadow-xl w-full max-w-6xl max-h-[90vh] overflow-y-auto"
      >
        <div class="p-6">
          <div class="flex justify-between items-center mb-4">
            <h2 class="text-2xl font-bold text-gray-800 dark:text-gray-200">
              Photo Details
            </h2>
            <button
              on:click={close}
              class="text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-6 w-6"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M6 18L18 6M6 6l12 12"
                />
              </svg>
            </button>
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
          {:else if error}
            <div
              class="bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200 p-4 rounded border border-red-200 dark:border-red-700"
            >
              Error loading photo details: {escapeHtml(error)}
            </div>
          {:else if photoDetails}
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
              <div class="text-center">
                <img
                  src="/photos/{photoDetails.photo_path}"
                  alt={photoDetails.task.output_filename}
                  class="max-w-full h-auto rounded-lg shadow-lg"
                />
              </div>

              <div class="lg:pl-5">
                <div class="mb-6">
                  <h3
                    class="mt-0 mb-3 text-gray-800 dark:text-gray-200 text-xl border-b-2 border-gray-200 dark:border-gray-600 pb-1"
                  >
                    Basic Information
                  </h3>
                  <div class="mb-3">
                    <span
                      class="font-bold text-gray-600 dark:text-gray-400 inline-block min-w-[140px]"
                      >Filename:</span
                    >
                    <span class="text-gray-800 dark:text-gray-200 break-words"
                      >{photoDetails.task.output_filename}</span
                    >
                  </div>
                  <div class="mb-3">
                    <span
                      class="font-bold text-gray-600 dark:text-gray-400 inline-block min-w-[140px]"
                      >Status:</span
                    >
                    <span
                      class="px-2 py-1 rounded text-sm font-bold uppercase {getStatusClass(
                        photoDetails.task.status,
                      )}">{photoDetails.task.status}</span
                    >
                  </div>
                  <div class="mb-3">
                    <span
                      class="font-bold text-gray-600 dark:text-gray-400 inline-block min-w-[140px]"
                      >User:</span
                    >
                    <span class="text-gray-800 dark:text-gray-200 break-words"
                      >{photoDetails.task.username || "Unknown"}</span
                    >
                  </div>
                  <div class="mb-3">
                    <span
                      class="font-bold text-gray-600 dark:text-gray-400 inline-block min-w-[140px]"
                      >Workflow Type:</span
                    >
                    <span class="text-gray-800 dark:text-gray-200 break-words"
                      >{photoDetails.task.workflow_type}</span
                    >
                  </div>
                </div>

                <div class="mb-6">
                  <h3
                    class="mt-0 mb-3 text-gray-800 dark:text-gray-200 text-xl border-b-2 border-gray-200 dark:border-gray-600 pb-1"
                  >
                    Timing
                  </h3>
                  <div class="mb-3">
                    <span
                      class="font-bold text-gray-600 dark:text-gray-400 inline-block min-w-[140px]"
                      >Queued At:</span
                    >
                    <span class="text-gray-800 dark:text-gray-200 break-words"
                      >{formatDate(photoDetails.task.queued_at)}</span
                    >
                  </div>
                  {#if photoDetails.task.started_at}
                    <div class="mb-3">
                      <span
                        class="font-bold text-gray-600 dark:text-gray-400 inline-block min-w-[140px]"
                        >Started At:</span
                      >
                      <span class="text-gray-800 dark:text-gray-200 break-words"
                        >{formatDate(photoDetails.task.started_at)}</span
                      >
                    </div>
                  {/if}
                  {#if photoDetails.task.completed_at}
                    <div class="mb-3">
                      <span
                        class="font-bold text-gray-600 dark:text-gray-400 inline-block min-w-[140px]"
                        >Completed At:</span
                      >
                      <span class="text-gray-800 dark:text-gray-200 break-words"
                        >{formatDate(photoDetails.task.completed_at)}</span
                      >
                    </div>
                  {/if}
                  {#if photoDetails.task.processing_time_seconds}
                    <div class="mb-3">
                      <span
                        class="font-bold text-gray-600 dark:text-gray-400 inline-block min-w-[140px]"
                        >Processing Time:</span
                      >
                      <span class="text-gray-800 dark:text-gray-200 break-words"
                        >{photoDetails.task.processing_time_seconds.toFixed(2)} seconds</span
                      >
                    </div>
                  {/if}
                </div>

                <div class="mb-6">
                  <h3
                    class="mt-0 mb-3 text-gray-800 dark:text-gray-200 text-xl border-b-2 border-gray-200 dark:border-gray-600 pb-1"
                  >
                    Prompt
                  </h3>
                  <div
                    class="bg-gray-50 dark:bg-gray-700 dark:text-gray-200 p-4 rounded font-mono text-sm whitespace-pre-wrap break-words"
                  >
                    {photoDetails.task.prompt || "N/A"}
                  </div>
                </div>

                {#if formatJson(photoDetails.task.parameters)}
                  <div class="mb-6">
                    <h3
                      class="mt-0 mb-3 text-gray-800 dark:text-gray-200 text-xl border-b-2 border-gray-200 dark:border-gray-600 pb-1"
                    >
                      Generation Parameters
                    </h3>
                    <div
                      class="bg-gray-50 dark:bg-gray-700 dark:text-gray-200 p-4 rounded font-mono text-sm overflow-x-auto"
                    >
                      {formatJson(photoDetails.task.parameters)}
                    </div>
                  </div>
                {/if}

                {#if formatJson(photoDetails.task.exif_data)}
                  <div class="mb-6">
                    <h3
                      class="mt-0 mb-3 text-gray-800 dark:text-gray-200 text-xl border-b-2 border-gray-200 dark:border-gray-600 pb-1"
                    >
                      EXIF Data
                    </h3>
                    <div
                      class="bg-gray-50 dark:bg-gray-700 dark:text-gray-200 p-4 rounded font-mono text-sm overflow-x-auto"
                    >
                      {formatJson(photoDetails.task.exif_data)}
                    </div>
                  </div>
                {/if}

                {#if photoDetails.task.error_message}
                  <div class="mb-6">
                    <h3
                      class="mt-0 mb-3 text-gray-800 dark:text-gray-200 text-xl border-b-2 border-gray-200 dark:border-gray-600 pb-1"
                    >
                      Error
                    </h3>
                    <div
                      class="bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200 p-4 rounded border border-red-200 dark:border-red-700"
                    >
                      {photoDetails.task.error_message}
                    </div>
                  </div>
                {/if}

                {#if photoDetails.task.comfyui_prompt_id}
                  <div class="mb-6">
                    <h3
                      class="mt-0 mb-3 text-gray-800 dark:text-gray-200 text-xl border-b-2 border-gray-200 dark:border-gray-600 pb-1"
                    >
                      Technical Details
                    </h3>
                    <div class="mb-3">
                      <span
                        class="font-bold text-gray-600 dark:text-gray-400 inline-block min-w-[140px]"
                        >Prompt ID:</span
                      >
                      <span class="text-gray-800 dark:text-gray-200 break-words"
                        >{photoDetails.task.comfyui_prompt_id}</span
                      >
                    </div>
                  </div>
                {/if}
              </div>
            </div>
          {/if}
        </div>
      </div>
    </div>
  </div>
</div>
