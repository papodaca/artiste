import "@hotwired/turbo";
import { Application } from "@hotwired/stimulus";
import CopyController from "./controllers/copy_controller.js";
import WebSocketController from "./controllers/websocket_controller.js";
import InfiniteScrollController from "./controllers/infinite_scroll_controller.js";
import ModalController from "./controllers/modal_controller.js";

const application = Application.start();
application.register("copy", CopyController);
application.register("websocket", WebSocketController);
application.register("infinite-scroll", InfiniteScrollController);
application.register("modal", ModalController);
