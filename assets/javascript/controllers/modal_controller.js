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

    // Listen for turbo frame loads to detect modal opening
    this.turboFrameLoadHandler = this.handleTurboFrameLoad.bind(this);
    if (this.hasFrameTarget) {
      this.frameTarget.addEventListener('turbo:frame-load', this.turboFrameLoadHandler);
    }

    // Check if modal should be open on connect (when navigating with query params)
    this.checkModalState();
  }

  disconnect() {
    document.removeEventListener('keydown', this.myHandler);
    if (this.turboFrameLoadHandler && this.hasFrameTarget) {
      this.frameTarget.removeEventListener('turbo:frame-load', this.turboFrameLoadHandler);
    }
    // Ensure body scroll is restored when controller is disconnected
    this.enableBodyScroll();
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
        // Restore body scroll
        this.enableBodyScroll();
      }, this.fadeOutDurationValue);
    } else {
      // Fallback if modal content is not found
      this.frameTarget.removeAttribute("src");
      this.frameTarget.childNodes.forEach(el => el.remove());
      // Remove query parameter from URL
      this.removeQueryParam();
      // Restore body scroll
      this.enableBodyScroll();
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

  checkModalState() {
    // Check if modal frame has content (is open)
    if (this.hasFrameTarget && this.frameTarget.getAttribute('src')) {
      this.disableBodyScroll();
    }
  }

  disableBodyScroll() {
    // Store current scroll position
    this.scrollY = window.scrollY;

    // Prevent body scroll when modal is open without jumping to top
    document.body.style.position = 'fixed';
    document.body.style.top = `-${this.scrollY}px`;
    document.body.style.width = '100%';
    document.body.style.overflow = 'hidden';
  }

  enableBodyScroll() {
    // Restore body scroll when modal is closed
    document.body.style.position = '';
    document.body.style.top = '';
    document.body.style.width = '';
    document.body.style.overflow = '';

    // Restore scroll position
    if (this.scrollY !== undefined) {
      window.scrollTo(0, this.scrollY);
      this.scrollY = undefined;
    }
  }

  handleTurboFrameLoad() {
    // When turbo frame loads, disable body scroll if modal content is present
    if (this.hasFrameTarget && this.frameTarget.getAttribute('src')) {
      this.disableBodyScroll();
    }
  }

  handleBackdropClick(event) {
    // Check if modal is open
    if (!this.hasFrameTarget || !this.frameTarget.getAttribute('src')) return;

    // Find the modal content element
    const modalContent = this.element.querySelector('[data-modal-target="content"]');
    if (!modalContent) return;

    // Find the actual modal content box (the white box with content)
    const modalBox = modalContent.querySelector('.max-w-6xl, .max-w-4xl, .max-w-2xl, .max-w-xl');
    if (!modalBox) return;

    // Check if click is outside the modal box (on the backdrop area)
    if (!modalBox.contains(event.target)) {
      this.close();
    }
  }

}