import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["trigger"];
  static values = {
    isLoading: { type: Boolean, default: false },
    offset: { type: Number, default: 0 },
    limit: { type: Number, default: 20 }
  };

  connect() {
    this.observer = null;
    this.initializeInfiniteScroll();
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect();
    }
  }

  initializeInfiniteScroll() {
    // Disconnect existing observer if any
    if (this.observer) {
      this.observer.disconnect();
    }

    if (!this.hasTriggerTarget) {
      console.log('No load-more-trigger found, infinite scroll disabled');
      return;
    }

    // Create an Intersection Observer to detect when the trigger is visible
    this.observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting && !this.isLoadingValue) {
          this.loadMorePhotos();
        }
      });
    }, {
      root: null, // viewport
      rootMargin: '100px', // start loading 100px before the trigger comes into view
      threshold: 0.1
    });

    this.observer.observe(this.triggerTarget);
  }

  async loadMorePhotos() {
    if (!this.hasTriggerTarget || this.isLoadingValue) return;

    this.isLoadingValue = true;

    try {
      const offset = this.triggerTarget.dataset.offset || this.offsetValue;
      const limit = this.triggerTarget.dataset.limit || this.limitValue;

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
          this.initializeInfiniteScroll();
        }, 100);
      } else {
        console.error('Failed to load more photos:', response.statusText);
      }
    } catch (error) {
      console.error('Error loading more photos:', error);
    } finally {
      this.isLoadingValue = false;
    }
  }
}