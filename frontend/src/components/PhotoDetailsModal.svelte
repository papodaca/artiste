<script>
  import { onMount } from 'svelte';
  import { formatDuration, intervalToDuration, formatRelative } from 'date-fns';

  const { selectedPhoto, onclose } = $props();
  let photoDetails = $state(null);
  let loading = $state(false);
  let error = $state(null);

  onMount(async () => {
    if (selectedPhoto) {
      await fetchPhotoDetails();
    }
  });

  async function fetchPhotoDetails() {
    loading = true;
    error = null;

    try {
      const response = await fetch(`/api/photo-details/${encodeURIComponent(selectedPhoto)}`);
      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.error || 'Failed to fetch photo details');
      }

      photoDetails = data;
    } catch (err) {
      console.error('Error loading photo details:', err);
      error = err.message;
    } finally {
      loading = false;
    }
  }

  function close() {
    onclose?.();
  }

  const statusClass = $derived.by(() => getStatusClass(photoDetails.task.status));

  function getStatusClass(status) {
    if (status === 'completed') return 'bg-status-completed-bg text-status-completed-text';
    if (status === 'processing') return 'bg-status-processing-bg text-status-processing-text';
    if (status === 'failed') return 'bg-status-failed-bg text-status-failed-text';
    return 'bg-status-pending-bg text-status-pending-text';
  }

  function formatDate(dateString) {
    if (!dateString) return 'N/A';
    try {
      const date = new Date(dateString);
      return formatRelative(date, new Date());
    } catch (error) {
      return dateString;
    }
  }

  function formatProcessingTime(seconds) {
    if (!seconds) return 'N/A';
    const duration = intervalToDuration({ start: 0, end: seconds * 1000 });
    return formatDuration(duration, { delimiter: ' ' });
  }

  function formatJson(obj) {
    if (!obj || Object.keys(obj).length === 0) return '';
    return JSON.stringify(obj, null, 2);
  }

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  function isVideo(path) {
    return path.toLowerCase().endsWith('.mp4');
  }
</script>

<div class="fixed inset-0 z-50">
  <div
    class="absolute inset-0 bg-black/50 backdrop-blur-sm"
    aria-hidden="true"
    onclick={close}
  ></div>
  <div class="fixed inset-0 overflow-y-auto">
    <div class="flex min-h-full items-center justify-center p-4">
      <div
        class="max-h-[90vh] w-full max-w-6xl overflow-y-auto rounded-lg bg-white shadow-xl dark:bg-gray-800"
      >
        <div class="p-6">
          <div class="mb-4 flex items-center justify-between">
            <h2 class="text-2xl font-bold text-gray-800 dark:text-gray-200">Photo Details</h2>
            <button
              onclick={close}
              class="text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
              aria-label="close"
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
            <div class="py-8 text-center">
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
              class="rounded border border-red-200 bg-red-100 p-4 text-red-800 dark:border-red-700 dark:bg-red-900 dark:text-red-200"
            >
              Error loading photo details: {escapeHtml(error)}
            </div>
          {:else if photoDetails}
            <div class="grid grid-cols-1 gap-8 lg:grid-cols-2">
              <div class="text-center">
                {#if isVideo(photoDetails.photo_path)}
                  <video
                    src="/photos/{photoDetails.photo_path}"
                    class="h-auto max-w-full rounded-lg shadow-lg"
                    autoplay
                    muted
                    loop
                  ></video>
                {:else}
                  <img
                    src="/photos/{photoDetails.photo_path}"
                    alt={photoDetails.task.output_filename}
                    class="h-auto max-w-full rounded-lg shadow-lg"
                  />
                {/if}
              </div>

              <div class="lg:pl-5">
                <div class="mb-6">
                  <h3
                    class="mb-3 mt-0 border-b-2 border-gray-200 pb-1 text-xl text-gray-800 dark:border-gray-600 dark:text-gray-200"
                  >
                    Basic Information
                  </h3>
                  <div class="mb-3">
                    <span
                      class="inline-block min-w-[140px] font-bold text-gray-600 dark:text-gray-400"
                      >Filename:</span
                    >
                    <span class="break-words text-gray-800 dark:text-gray-200"
                      >{photoDetails.task.output_filename}</span
                    >
                  </div>
                  <div class="mb-3">
                    <span
                      class="inline-block min-w-[140px] font-bold text-gray-600 dark:text-gray-400"
                      >Status:</span
                    >
                    <span class="rounded px-2 py-1 text-sm font-bold uppercase {statusClass}"
                      >{photoDetails.task.status}</span
                    >
                  </div>
                  <div class="mb-3">
                    <span
                      class="inline-block min-w-[140px] font-bold text-gray-600 dark:text-gray-400"
                      >User:</span
                    >
                    <span class="break-words text-gray-800 dark:text-gray-200"
                      >{photoDetails.task.username || 'Unknown'}</span
                    >
                  </div>
                  <div class="mb-3">
                    <span
                      class="inline-block min-w-[140px] font-bold text-gray-600 dark:text-gray-400"
                      >Workflow Type:</span
                    >
                    <span class="break-words text-gray-800 dark:text-gray-200"
                      >{photoDetails.task.workflow_type}</span
                    >
                  </div>
                </div>

                <div class="mb-6">
                  <h3
                    class="mb-3 mt-0 border-b-2 border-gray-200 pb-1 text-xl text-gray-800 dark:border-gray-600 dark:text-gray-200"
                  >
                    Timing
                  </h3>
                  <div class="mb-3">
                    <span
                      class="inline-block min-w-[140px] font-bold text-gray-600 dark:text-gray-400"
                      >Completed At:</span
                    >
                    <span class="break-words text-gray-800 dark:text-gray-200"
                      >{formatDate(photoDetails.task.completed_at)}</span
                    >
                  </div>
                  <div class="mb-3">
                    <span
                      class="inline-block min-w-[140px] font-bold text-gray-600 dark:text-gray-400"
                      >Processing Time:</span
                    >
                    <span class="break-words text-gray-800 dark:text-gray-200"
                      >{formatProcessingTime(photoDetails.task.processing_time_seconds)}</span
                    >
                  </div>
                </div>

                <div class="mb-6">
                  <h3
                    class="mb-3 mt-0 border-b-2 border-gray-200 pb-1 text-xl text-gray-800 dark:border-gray-600 dark:text-gray-200"
                  >
                    Prompt
                  </h3>
                  <div
                    class="whitespace-pre-wrap break-words rounded bg-gray-50 p-4 font-mono text-sm dark:bg-gray-700 dark:text-gray-200"
                  >
                    {photoDetails.task.prompt || 'N/A'}
                  </div>
                </div>

                {#if formatJson(photoDetails.task.parameters)}
                  <div class="mb-6">
                    <h3
                      class="mb-3 mt-0 border-b-2 border-gray-200 pb-1 text-xl text-gray-800 dark:border-gray-600 dark:text-gray-200"
                    >
                      Generation Parameters
                    </h3>
                    <div
                      class="overflow-x-auto rounded bg-gray-50 p-4 font-mono text-sm dark:bg-gray-700 dark:text-gray-200"
                    >
                      {formatJson(photoDetails.task.parameters)}
                    </div>
                  </div>
                {/if}

                {#if formatJson(photoDetails.task.exif_data)}
                  <div class="mb-6">
                    <h3
                      class="mb-3 mt-0 border-b-2 border-gray-200 pb-1 text-xl text-gray-800 dark:border-gray-600 dark:text-gray-200"
                    >
                      EXIF Data
                    </h3>
                    <div
                      class="overflow-x-auto rounded bg-gray-50 p-4 font-mono text-sm dark:bg-gray-700 dark:text-gray-200"
                    >
                      {formatJson(photoDetails.task.exif_data)}
                    </div>
                  </div>
                {/if}

                {#if photoDetails.task.error_message}
                  <div class="mb-6">
                    <h3
                      class="mb-3 mt-0 border-b-2 border-gray-200 pb-1 text-xl text-gray-800 dark:border-gray-600 dark:text-gray-200"
                    >
                      Error
                    </h3>
                    <div
                      class="rounded border border-red-200 bg-red-100 p-4 text-red-800 dark:border-red-700 dark:bg-red-900 dark:text-red-200"
                    >
                      {photoDetails.task.error_message}
                    </div>
                  </div>
                {/if}

                {#if photoDetails.task.comfyui_prompt_id}
                  <div class="mb-6">
                    <h3
                      class="mb-3 mt-0 border-b-2 border-gray-200 pb-1 text-xl text-gray-800 dark:border-gray-600 dark:text-gray-200"
                    >
                      Technical Details
                    </h3>
                    <div class="mb-3">
                      <span
                        class="inline-block min-w-[140px] font-bold text-gray-600 dark:text-gray-400"
                        >Prompt ID:</span
                      >
                      <span class="break-words text-gray-800 dark:text-gray-200"
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
