import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["item", "checkbox"];
  static values = {
    selectedIds: Array,
    lastClickedIndex: Number,
  };

  connect() {
    this.selectedIdsValue = [];
    this.lastClickedIndexValue = -1;
    this.updateButtonStatus();
    this.selectedIdsValueChanged();
    this.setupToggleSwitches();
  }

  selectedIdsValueChanged() {
    this.itemTargets.forEach(item => {
      const photoId = item.dataset.photoId;
      const isSelected = this.selectedIdsValue.includes(photoId);
      const overlay = item.querySelector('.selected-overlay');
      const checkboxContainer = item.querySelector('.absolute.left-2.top-2.z-10');

      if (isSelected) {
        item.classList.add('ring-2', 'ring-blue-500', 'ring-offset-2');
        if (overlay) {
          overlay.classList.remove('opacity-0');
          overlay.classList.add('opacity-20');
        }
        if (checkboxContainer) {
          checkboxContainer.setAttribute('data-selected', 'true');
        }
      } else {
        item.classList.remove('ring-2', 'ring-blue-500', 'ring-offset-2');
        if (overlay) {
          overlay.classList.remove('opacity-20');
          overlay.classList.add('opacity-0');
        }
        if (checkboxContainer) {
          checkboxContainer.removeAttribute('data-selected');
        }
      }
    });
  }

  toggleSelection(event) {
    // Ignore right-click or non-left mouse button events to prevent unwanted selection
    const isRightClick = event.type === 'contextmenu' || (event.button !== undefined && event.button !== 0);
    if (isRightClick) {
      return;
    }
    const checkbox = event.target;
    const photoItem = checkbox.closest('[data-photo-selection-target="item"]');
    const photoId = photoItem.dataset.photoId;
    const allItems = Array.from(this.itemTargets);
    const currentIndex = allItems.indexOf(photoItem);

    // Handle shift-click for range selection
    if (event.shiftKey && this.lastClickedIndexValue !== -1) {
      // Prevent default checkbox behavior for shift-click
      event.preventDefault();
      this.selectRange(currentIndex);
    } else {
      // For normal clicks, let the browser handle the checkbox toggle
      // We'll update our state based on what the checkbox will be after the click
      const willBeChecked = !checkbox.checked;

      if (willBeChecked) {
        // Add to selected IDs if not already present
        if (!this.selectedIdsValue.includes(photoId)) {
          this.selectedIdsValue = [...this.selectedIdsValue, photoId];
        }
      } else {
        // Remove from selected IDs
        this.selectedIdsValue = this.selectedIdsValue.filter(id => id !== photoId);
      }

      // Update last clicked index
      this.lastClickedIndexValue = currentIndex;
    }

    this.updateButtonStatus();
  }

  selectRange(endIndex) {
    const allItems = Array.from(this.itemTargets);
    const startIndex = this.lastClickedIndexValue;
    const endItem = allItems[endIndex];
    const endPhotoId = endItem.dataset.photoId;
    const endCheckbox = endItem.querySelector('[data-photo-selection-target="checkbox"]');

    // Determine if we should select or deselect based on the end item's current state
    const shouldSelect = !this.selectedIdsValue.includes(endPhotoId);

    // Determine the range direction
    const minIndex = Math.min(startIndex, endIndex);
    const maxIndex = Math.max(startIndex, endIndex);

    // Toggle all items in the range
    for (let ii = minIndex; ii <= maxIndex; ii++) {
      const item = allItems[ii];
      const photoId = item.dataset.photoId;
      const checkbox = item.querySelector('[data-photo-selection-target="checkbox"]');

      if (checkbox) {
        if (shouldSelect && !this.selectedIdsValue.includes(photoId)) {
          if (ii !== maxIndex && ii !== minIndex)
            checkbox.checked = true;
          this.selectedIdsValue = [...this.selectedIdsValue, photoId];
        } else if (!shouldSelect && this.selectedIdsValue.includes(photoId)) {
          if (ii !== maxIndex && ii !== minIndex)
            checkbox.checked = false;
          this.selectedIdsValue = this.selectedIdsValue.filter(id => id !== photoId);
        }
      }
    }
    // Update last clicked index
    this.lastClickedIndexValue = endIndex;
  }

  selectAll() {
    this.checkboxTargets.forEach((checkbox, index) => {
      if (!checkbox.checked) {
        checkbox.checked = true;
        const photoId = checkbox.closest('[data-photo-selection-target="item"]').dataset.photoId;
        if (!this.selectedIdsValue.includes(photoId)) {
          this.selectedIdsValue = [...this.selectedIdsValue, photoId];
        }
      }
    });
    // Reset last clicked index when selecting all
    this.lastClickedIndexValue = -1;
    this.updateButtonStatus();
  }

  deselectAll() {
    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = false;
    });
    this.selectedIdsValue = [];
    // Reset last clicked index when deselecting all
    this.lastClickedIndexValue = -1;
    this.updateButtonStatus();
  }

  updateButtonStatus() {
    const deleteButton = document.getElementById('delete-selected-button');
    const makePrivateButton = document.getElementById('make-private-button');
    const makePublicButton = document.getElementById('make-public-button');

    const hasSelection = this.selectedIdsValue.length > 0;

    if (deleteButton) {
      deleteButton.disabled = !hasSelection;
      deleteButton.textContent = `Delete Selected (${this.selectedIdsValue.length})`;
    }

    if (makePrivateButton) {
      makePrivateButton.disabled = !hasSelection;
    }

    if (makePublicButton) {
      makePublicButton.disabled = !hasSelection;
    }
  }

  async deleteSelected() {
    if (this.selectedIdsValue.length === 0) return;

    if (!confirm(`Are you sure you want to delete ${this.selectedIdsValue.length} selected photo(s)? This action cannot be undone.`)) {
      return;
    }

    try {
      const response = await fetch('/api/photos/delete', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({
          photo_ids: this.selectedIdsValue
        })
      });

      if (!response.ok) {
        throw new Error('Failed to delete photos');
      }

      const result = await response.json();

      // Remove deleted items from DOM
      this.selectedIdsValue.forEach(photoId => {
        const item = document.querySelector(`[data-photo-id="${photoId}"]`);
        if (item) {
          item.remove();
        }
      });

      // Clear selection
      this.selectedIdsValue = [];
      this.lastClickedIndexValue = -1;
      this.updateButtonStatus();

      // Show success message
      this.showNotification('Photos deleted successfully', 'success');

    } catch (error) {
      console.error('Error deleting photos:', error);
      this.showNotification('Failed to delete photos', 'error');
    }
  }

  getCSRFToken() {
    const metaTag = document.querySelector('meta[name="csrf-token"]');
    return metaTag ? metaTag.getAttribute('content') : '';
  }

  async makePrivate() {
    if (this.selectedIdsValue.length === 0) return;

    try {
      const response = await fetch('/api/photos/make-private', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({
          photo_ids: this.selectedIdsValue
        })
      });

      if (!response.ok) {
        throw new Error('Failed to make photos private');
      }

      const result = await response.json();

      // Update the UI for each photo that was made private
      this.selectedIdsValue.forEach(photoId => {
        const photoItem = document.querySelector(`[data-photo-id="${photoId}"]`);
        const checkbox = photoItem.querySelector('input[type="checkbox"]')
        if (checkbox)
          checkbox.checked = false;
        if (photoItem)
          photoItem.classList.add('border-2', 'border-blue-500', 'dark:border-blue-400');
      });

      // Show success message
      this.showNotification(`Made ${result.updated_count} photo(s) private`, 'success');

      // Clear selection
      this.selectedIdsValue = [];
      this.lastClickedIndexValue = -1;
      this.updateButtonStatus();

    } catch (error) {
      console.error('Error making photos private:', error);
      this.showNotification('Failed to make photos private', 'error');
    }
  }

  async makePublic() {
    if (this.selectedIdsValue.length === 0) return;

    try {
      const response = await fetch('/api/photos/make-public', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({
          photo_ids: this.selectedIdsValue
        })
      });

      if (!response.ok) {
        throw new Error('Failed to make photos public');
      }

      const result = await response.json();

      // Update the UI for each photo that was made public
      this.selectedIdsValue.forEach(photoId => {
        const photoItem = document.querySelector(`[data-photo-id="${photoId}"]`);
        const checkbox = photoItem.querySelector('input[type="checkbox"]')
        if (checkbox)
          checkbox.checked = false;
        if (photoItem)
          photoItem.classList.remove('border-2', 'border-blue-500', 'dark:border-blue-400');
      });

      // Show success message
      this.showNotification(`Made ${result.updated_count} photo(s) public`, 'success');

      // Clear selection
      this.selectedIdsValue = [];
      this.lastClickedIndexValue = -1;
      this.updateButtonStatus();

    } catch (error) {
      console.error('Error making photos public:', error);
      this.showNotification('Failed to make photos public', 'error');
    }
  }

  showNotification(message, type = 'info') {
    // Create notification element
    const notification = document.createElement('div');
    notification.className = `fixed top-4 right-4 z-50 p-4 rounded-lg shadow-lg ${type === 'success' ? 'bg-green-500 text-white' :
      type === 'error' ? 'bg-red-500 text-white' :
        'bg-blue-500 text-white'
      }`;
    notification.textContent = message;

    document.body.appendChild(notification);

    // Remove after 3 seconds
    setTimeout(() => {
      notification.remove();
    }, 3000);
  }

  setupToggleSwitches() {
    const toggleSwitches = this.element.querySelectorAll('.toggle-switch');

    toggleSwitches.forEach(toggle => {
      toggle.addEventListener('change', (event) => {
        this.updateUrlAndReload(event.target);
      });
    });
  }

  updateUrlAndReload(toggle) {
    const url = new URL(window.location);
    const param = toggle.dataset.param;
    toggle.checked ? url.searchParams.set(param, 'true') : url.searchParams.delete(param)
    window.location.href = url.toString();
  }
}