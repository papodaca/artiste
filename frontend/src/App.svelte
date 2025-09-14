<script>
  import PhotoGallery from "./components/PhotoGallery.svelte";
</script>

<PhotoGallery />

<style>
  :global(body) {
    font-family: system-ui, Avenir, Helvetica, Arial, sans-serif;
    line-height: 1.5;
    font-weight: 400;
    color-scheme: light dark;
    color: rgba(255, 255, 255, 0.87);
    background-color: #242424;
    margin: 0;
    min-width: 320px;
    min-height: 100vh;
  }

  @media (prefers-color-scheme: light) {
    :global(body) {
      color: #213547;
      background-color: #ffffff;
    }
  }

  /* Grid background pattern */
  :global(body) {
    background-image: linear-gradient(
        rgba(156, 163, 175, 0.2) 1px,
        transparent 1px
      ),
      linear-gradient(90deg, rgba(156, 163, 175, 0.2) 1px, transparent 1px);
    background-size: 20px 20px;
  }

  :global(.dark body) {
    background-image: linear-gradient(
        rgba(75, 85, 99, 0.2) 1px,
        transparent 1px
      ),
      linear-gradient(90deg, rgba(75, 85, 99, 0.2) 1px, transparent 1px);
  }

  /* Status colors */
  :global(.bg-status-completed-bg) {
    background-color: #d4edda;
  }

  :global(.text-status-completed-text) {
    color: #155724;
  }

  :global(.bg-status-processing-bg) {
    background-color: #fff3cd;
  }

  :global(.text-status-processing-text) {
    color: #856404;
  }

  :global(.bg-status-failed-bg) {
    background-color: #f8d7da;
  }

  :global(.text-status-failed-text) {
    color: #721c24;
  }

  :global(.bg-status-pending-bg) {
    background-color: #d1ecf1;
  }

  :global(.text-status-pending-text) {
    color: #0c5460;
  }
</style>
