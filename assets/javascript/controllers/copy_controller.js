import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { photoPath: String };

  async copy(event) {
    event.stopPropagation();
    const button = this.element;

    try {
      const fullUrl = window.location.origin + this.photoPathValue;
      await navigator.clipboard.writeText(fullUrl);
      const originalHTML = button.innerHTML;

      button.innerHTML = '<div class="text-green-600 dark:text-green-500 icon-check"></div>';
      setTimeout(() => {
        button.innerHTML = originalHTML;
      }, 1500);
    } catch (error) {
      console.error('Error copying URL:', error);
    }
  }
}
