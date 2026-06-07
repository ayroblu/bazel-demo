import { insertText } from "./insert-text";
import { mode } from "./mode-helper";
import { log } from "./log";
import { addMessageListener, sendMessage } from "./messaging";
import { setupScrollListener } from "./scroll";
import { getIsInputTarget, getKeymap } from "./keymaps";
import { getKey } from "./utils";

sendMessage<"greeting">({ type: "greeting", greeting: "hello" }).then(
  (response) => {
    log("Received response: ", response?.farewell);
  }
);

const disposeMessageListener = addMessageListener(
  (request, _sender, _sendResponse) => {
    log("Received request: ", request);
  }
);

addEventListener("keydown", handleKeyEvent, true);
const disposeKeydownListener = () => {
  removeEventListener("keydown", handleKeyEvent, true);
};

const disposeScrollListener = setupScrollListener();

// when rebuilding our extension, safari immediately remounts the script so we end up with two event listeners.
// the background script however is fully unmounted, so the promise will always return undefined
// List to focus events and unmount old scripts
// Note: we can't simply add a listener to window
function focusHandler() {
  sendMessage({ type: "greeting", greeting: "hello" })
    .then((response) => {
      if (response) return;
      disposeFocusHandler();
      disposeMessageListener();
      disposeKeydownListener();
      disposeScrollListener();
    })
    .catch((err) => log("err", err));
}
window.addEventListener("focus", focusHandler);
function disposeFocusHandler() {
  window.removeEventListener("focus", focusHandler);
}

function handleKeyEvent(event: KeyboardEvent) {
  const key = getKey(event);
  const keymap = getKeymap(event);
  log("key", key, "state", mode.getState(), keymap);
  const mapped = (mode.getState() ?? keymap)[key];
  // I don't think this handles modifier presses well
  if (mapped) {
    log("mapped", mapped);
    event.preventDefault();
    if (typeof mapped === "function") {
      mode.setState(null);
      mode.clearInsertState();
      mapped();
    } else {
      if (getIsInsertInput(event)) {
        const char = event.key;
        if (char.length === 1) {
          mode.addInsertState(char);
        }
      }
      mode.setState(mapped);
    }
  } else if (keymap.other && typeof keymap.other === "function") {
    log("other firing");
    event.preventDefault();
    mode.setState(null);
    mode.clearInsertState();
    keymap.other();
  } else {
    if (
      getIsInsertInput(event) &&
      event.target instanceof HTMLElement &&
      mode.insertState
    ) {
      event.preventDefault();
      insertText(event.target, mode.insertState);
    }
    mode.setState(null);
    mode.clearInsertState();
  }
}

function getIsInsertInput(event: KeyboardEvent) {
  return mode.value === "insert" && getIsInputTarget(event);
}
