import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["frame", "content"];
  static values = {
    queryParam: String,
    fadeOutDuration: { type: Number, default: 300 }
  };

  connect() {
    // Add ESC key listener to close modal
    this.keydownHandler = this.handleKeydown.bind(this);
    this.myHandler = this.keydownHandler.bind(this)
    document.addEventListener('keydown', this.myHandler);
  }

  disconnect() {
    document.removeEventListener('keydown', this.myHandler);
  }

  close() {
    if (!this.hasFrameTarget) return;

    // Add fade-out animation to the modal content
    if (this.hasContentTarget) {
      this.contentTarget.classList.add('fade-out');

      // Wait for the animation to complete before removing the modal
      setTimeout(() => {
        this.frameTarget.removeAttribute("src");
        this.contentTarget.remove();
        // Remove query parameter from URL
        this.removeQueryParam();
      }, this.fadeOutDurationValue);
    } else {
      // Fallback if modal content is not found
      this.frameTarget.removeAttribute("src");
      this.frameTarget.childNodes.forEach(el => el.remove());
      // Remove query parameter from URL
      this.removeQueryParam();
    }
  }

  handleKeydown(event) {
    if (event.key === 'Escape') {
      this.close();
    }
  }

  removeQueryParam() {
    if (!this.queryParamValue) return;

    const url = new URL(window.location);
    url.searchParams.delete(this.queryParamValue);
    const newUrl = url.pathname + url.search;
    window.history.replaceState({}, '', newUrl);
  }
}