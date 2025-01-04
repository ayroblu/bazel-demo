"use strict";
(() => {
  // src/insert-text.ts
  function insertText(textField, text) {
    if (textField instanceof HTMLInputElement || textField instanceof HTMLTextAreaElement) {
      if (textField.selectionStart || textField.selectionStart === 0) {
        const startPos = textField.selectionStart;
        const endPos = textField.selectionEnd;
        textField.value = textField.value.substring(0, startPos) + text + (endPos ? textField.value.substring(endPos, textField.value.length) : "");
      } else {
        textField.value += text;
      }
    } else {
      insertTextAtCaretContentEditable(text);
    }
  }
  function insertTextAtCaretContentEditable(text) {
    if (window.getSelection) {
      const sel = window.getSelection();
      if (sel && sel.getRangeAt && sel.rangeCount) {
        const range = sel.getRangeAt(0);
        range.deleteContents();
        range.insertNode(document.createTextNode(text));
      }
    }
  }

  // src/mode-helper.ts
  var mode = modeHelper();
  function modeHelper() {
    let mode2 = "normal";
    let state = null;
    let insertState = [];
    return {
      get value() {
        return mode2;
      },
      set value(newMode) {
        if (newMode === mode2)
          return;
        state = null;
        insertState = [];
        mode2 = newMode;
      },
      getState: () => state,
      setState: (newState) => {
        state = newState;
      },
      clearInsertState: () => {
        if (insertState.length) {
          insertState = [];
        }
      },
      get insertState() {
        return insertState.join("");
      },
      addInsertState: (key) => {
        insertState.push(key);
      }
    };
  }

  // src/log.ts
  var debug = false;
  function log(...args) {
    if (debug) {
      console.log(...args);
    }
  }

  // src/messaging.ts
  function addMessageListener(cb) {
    const callback = cb;
    browser.runtime.onMessage.addListener(callback);
    return () => {
      browser.runtime.onMessage.removeListener(callback);
    };
  }
  function sendMessage(req) {
    return browser.runtime.sendMessage(req);
  }

  // src/scroll.ts
  function getScrollable() {
    if (lastTarget) {
      log("lastTarget", lastTarget);
      return lastTarget;
    }
    if (document.documentElement.scrollHeight > document.documentElement.clientHeight) {
      lastTarget = window;
      return lastTarget;
    }
    if (document.body.scrollHeight > document.body.clientHeight) {
      lastTarget = document.body;
      return lastTarget;
    }
    const items = [...document.querySelectorAll("*")].filter(
      (el) => el instanceof HTMLElement && el.clientHeight > 0 && el.scrollHeight > el.clientHeight && (() => {
        const overflowY = window.getComputedStyle(el).overflowY;
        return overflowY !== "visible" && overflowY !== "hidden";
      })()
    );
    if (items.length === 0) {
      return window;
    }
    let maxArea = 0;
    let maxItem = items[0];
    for (const item of items) {
      const area = item.clientWidth * item.clientHeight;
      if (area > maxArea) {
        maxArea = area;
        maxItem = item;
      }
    }
    lastTarget = maxItem;
    return maxItem;
  }
  var lastTarget = null;
  var eventListener = (event) => {
    if (event.target === document) {
      lastTarget = window;
    }
    if (event.target instanceof HTMLElement) {
      lastTarget = event.target;
    }
  };
  var scrollHalfPage = (direction) => {
    const scrollable = getScrollable();
    const scrollableHeight = scrollable instanceof HTMLElement ? scrollable.clientHeight : window.innerHeight;
    getScrollable().scrollBy(
      0,
      (direction === "up" ? -1 : 1) * Math.min(window.innerHeight, scrollableHeight) / 2
    );
  };
  function handleScrollToBottom() {
    const scrollable = getScrollable();
    const scrollElement = scrollable instanceof HTMLElement ? scrollable : document.body;
    scrollable.scrollTo(0, scrollElement.scrollHeight);
  }
  function setupScrollListener() {
    addEventListener("scroll", eventListener, { passive: true, capture: true });
    return () => {
      removeEventListener("scroll", eventListener, { capture: true });
    };
  }
  function resetScrollable() {
    lastTarget = window;
  }

  // src/links-tags.ts
  var highlights = [];
  var typedState = "";
  function showLinkTags() {
    const bodyRect = document.body.getBoundingClientRect();
    let items = [...document.querySelectorAll("*")].filter(
      (el) => el instanceof HTMLElement && isElementInViewport(el) && !isHidden(el) && (["BUTTON", "A", "INPUT"].includes(el.tagName) || el.role === "button" || !!el.onclick || window.getComputedStyle(el).cursor == "pointer")
    ).map(function(element) {
      var rect = element.getBoundingClientRect();
      return {
        element,
        rect: {
          left: Math.max(rect.left - bodyRect.x, 0),
          top: Math.max(rect.top - bodyRect.y, 0),
          right: Math.min(rect.right - bodyRect.x, document.body.clientWidth),
          bottom: Math.min(
            rect.bottom - bodyRect.y,
            document.body.clientHeight
          )
        },
        text: element.textContent?.trim().replace(/\s{2,}/g, " ")
      };
    }).filter(
      (item) => (item.rect.right - item.rect.left) * (item.rect.bottom - item.rect.top) >= 20
    );
    items = items.filter(
      (x) => !items.some((y) => x.element.contains(y.element) && !(x == y))
    );
    highlights.forEach(({ el }) => el.remove());
    highlights = items.map((item, i) => {
      const newElement = document.createElement("div");
      newElement.style.outline = "2px dashed rgba(255,0,0,.75)";
      newElement.style.position = "absolute";
      newElement.style.left = item.rect.left + "px";
      newElement.style.top = item.rect.top + "px";
      newElement.style.width = item.rect.right - item.rect.left + "px";
      newElement.style.height = item.rect.bottom - item.rect.top + "px";
      newElement.style.pointerEvents = "none";
      newElement.style.boxSizing = "border-box";
      newElement.style.zIndex = "2147483647";
      const labelElement = document.createElement("div");
      newElement.appendChild(labelElement);
      Object.assign(labelElement.style, {
        top: "0",
        left: "0",
        backgroundColor: "#fcba03",
        borderRadius: "4px",
        fontWeight: "bold",
        fontSize: "1.15rem",
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
        padding: "4px 8x",
        display: "inline-block",
        color: "black",
        border: "1px solid #553300"
      });
      const iLabel = i + Math.pow(10, Math.max((items.length - 1).toString().length - 1, 0)) + "";
      labelElement.innerText = iLabel;
      document.body.appendChild(newElement);
      return {
        el: newElement,
        rect: item.rect,
        text: item.text,
        originalEl: item.element,
        numLabel: iLabel,
        setEligible: (eligible) => {
          if (!eligible) {
            Object.assign(newElement.style, {
              opacity: "0.2"
            });
          } else {
            Object.assign(newElement.style, {
              opacity: "1"
            });
          }
        }
      };
    });
    if (highlights.length) {
      mode.value = "links";
    }
  }
  function clearLinks() {
    highlights.forEach(({ el }) => el.remove());
    highlights = [];
    mode.value = "normal";
    typedState = "";
  }
  function handleLinkFn(char) {
    return () => {
      const resultText = char === "Backspace" ? typedState.slice(0, -1) : typedState + char;
      const eligibleHighlights = highlights.filter(
        ({ numLabel, setEligible }) => {
          const isEligible = numLabel.startsWith(resultText);
          setEligible(isEligible);
          return isEligible;
        }
      );
      if (eligibleHighlights.length === 0) {
        clearLinks();
      } else if (eligibleHighlights.length === 1) {
        const clickEvent = new MouseEvent("click", {
          view: window,
          bubbles: true,
          cancelable: false
        });
        eligibleHighlights[0].originalEl.dispatchEvent(clickEvent);
        clearLinks();
      } else {
        typedState = resultText;
      }
    };
  }
  function isElementInViewport(el) {
    var rect = el.getBoundingClientRect();
    return rect.top >= 0 && rect.left >= 0 && rect.bottom <= (window.innerHeight || document.documentElement.clientHeight) && rect.right <= (window.innerWidth || document.documentElement.clientWidth);
  }
  function isHidden(el) {
    const style = window.getComputedStyle(el);
    return style.display === "none" || style.visibility === "hidden" || style.pointerEvents === "none";
  }
  function nextInput() {
    let inputs = [
      ...document.querySelectorAll("input[type=text],textarea")
    ].filter(filterInputs);
    if (!inputs.length) {
      inputs = getAllInputsIncludingWebComponents();
      if (!inputs.length) {
        return;
      }
    }
    const activeElement = document.activeElement;
    let nextIndex = 0;
    if (activeElement instanceof HTMLInputElement) {
      const index = inputs.indexOf(activeElement);
      if (index !== -1) {
        nextIndex = index + 1 % inputs.length;
      }
    }
    inputs[nextIndex].focus();
  }
  function getAllInputsIncludingWebComponents(root = document) {
    const inputs = [];
    inputs.push(...root.querySelectorAll("input[type=text],textarea"));
    root.querySelectorAll("*").forEach((element) => {
      if (element.shadowRoot) {
        inputs.push(...getAllInputsIncludingWebComponents(element.shadowRoot));
      }
    });
    return inputs.filter(filterInputs);
  }
  function filterInputs(element) {
    return (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) && isElementInViewport(element) && !isHidden(element) && !element.disabled;
  }

  // src/utils.ts
  function collect(arr, fn) {
    if (!arr.length) {
      return [];
    }
    return arr.reduce((newArr, next) => {
      const result = fn(next);
      if (result !== null && result !== void 0) {
        newArr.push(result);
      }
      return newArr;
    }, []);
  }
  function getKey(event) {
    return [
      event.ctrlKey ? "C-" : null,
      event.metaKey ? "M-" : null,
      event.altKey ? "A-" : null,
      event.shiftKey && (event.ctrlKey || event.metaKey || event.altKey) ? "S-" : null
    ].filter(Boolean).join("") + event.key;
  }

  // src/search-bar.ts
  var mountedBar = null;
  async function showSearchTabs() {
    const searchBar = getSearchBar();
    const tabs = await sendMessage({
      type: "searchTabs",
      query: ""
    });
    const items = collect(
      tabs,
      ({ id, title, url }) => title && id !== void 0 ? {
        id: id + "",
        onSelect: () => sendMessage({ type: "focusTab", id }),
        title,
        subtitle: url
      } : null
    );
    searchBar.setItems(items);
  }
  function getSearchBar() {
    if (!mountedBar) {
      mountedBar = createSearchBar();
    }
    mountedBar.show();
    mode.value = "search";
    return mountedBar;
  }
  function createSearchBar() {
    const el = SearchBar.create();
    document.body.appendChild(el);
    return el;
  }
  function hideSearchBar() {
    if (!mountedBar)
      return;
    mountedBar.hide();
    mode.value = "normal";
  }
  var _CustomElement = class extends HTMLElement {
    static define() {
      const name = this.elementName;
      if (name === "placeholder") {
        throw new Error("Abstract class CustomElement name must be changed.");
      }
      if (customElements.get(name)) {
        log(name, "already defined");
        return;
      }
      customElements.define(name, this);
    }
    static create() {
      const name = this.elementName;
      return document.createElement(name);
    }
    constructor() {
      super();
      if (this.constructor == _CustomElement) {
        throw new Error("Abstract class CustomElement can't be instantiated.");
      }
    }
  };
  var CustomElement = _CustomElement;
  CustomElement.elementName = "placeholder";
  var SearchBar = class extends CustomElement {
    constructor() {
      super(...arguments);
      this.container = null;
      this.input = null;
      this.list = null;
      this.handleSearch = () => {
        if (!this.input)
          return;
        const query = this.input.value;
        this.items?.handleSearch((items) => {
          const queryParts = query.toLowerCase().split(/\s+/g);
          const filteredItems = items.reduce((list, item) => {
            const isVisible = queryParts.every(
              (queryPart) => item.title?.includes(queryPart) || item.subtitle?.includes(queryPart)
            );
            if (isVisible) {
              list.push(item);
              this.list.appendChild(item.el);
            } else {
              item.el.remove();
            }
            return list;
          }, []);
          return filteredItems;
        });
      };
      this.handleKeydown = (event) => {
        if (!this.list)
          return;
        const key = getKey(event);
        if (["ArrowDown", "C-n"].includes(key)) {
          event.preventDefault();
          this.items?.increaseSelected();
        } else if (["ArrowUp", "C-p"].includes(key)) {
          event.preventDefault();
          this.items?.decreaseSelected();
        } else if (["Enter"].includes(key)) {
          event.preventDefault();
          this.items?.handleSelected();
          this.hide();
        }
      };
      this.hide = () => {
        const container = this.container;
        if (!container)
          return;
        container.style.display = "none";
        mode.value = "normal";
      };
      this.show = () => {
        const container = this.container;
        if (!container)
          return;
        const input = this.input;
        input.focus();
        input.value = "";
        const list = this.list;
        list.innerHTML = "";
        container.style.display = "flex";
        if (!this.input)
          return;
        this.input.oninput = this.handleSearch;
        this.input.onkeydown = this.handleKeydown;
      };
      this.items = null;
      this.setItems = (items) => {
        const list = this.list;
        if (!list)
          return;
        list.innerHTML = "";
        const itemsWithEl = items.map((item) => {
          const el = document.createElement("div");
          el.classList.add("item");
          const titleEl = document.createElement("h3");
          titleEl.innerText = item.title;
          el.appendChild(titleEl);
          if (item.subtitle) {
            const subtitleEl = document.createElement("p");
            subtitleEl.innerText = item.subtitle;
            el.appendChild(subtitleEl);
          }
          list.appendChild(el);
          return {
            ...item,
            el
          };
        });
        this.items?.dispose();
        this.items = itemsFilterFn(itemsWithEl);
      };
    }
    connectedCallback() {
      const shadow = this.attachShadow({ mode: "open" });
      shadow.innerHTML = `
<style>
h3, p {
  margin: 0;
  font-size: 16px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.search-bar {
  width: 80vw;
  max-height: 60vh;
  background-color: black;
  color: white;
  position: fixed;
  top: 20vh;
  left: 50%;
  transform: translateX(-50%);
  z-index: 2147483647;
  border: 1px solid #888;
  border-radius: 8px;
  display: flex;
  flex-direction: column;
}
.input {
  width: 100%;
  font-size: 24px;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  padding: 4px 8px;
  box-sizing: border-box;
}
.item {
  border-bottom: 1px solid #888;
  padding: 4px 8px;
}
.selected {
  background-color: #58c;
}
.list {
  overflow: auto;
}
</style>
<div class="search-bar">
  <input class="input" />
  <div class="list" />
</div>
    `;
      this.container = shadow.querySelector(".search-bar");
      this.input = shadow.querySelector(".input");
      this.list = shadow.querySelector(".list");
      this.input?.focus();
    }
  };
  SearchBar.elementName = "vimkey-seach-bar";
  function itemsFilterFn(items) {
    let filteredItems = items;
    let selectedIndex = 0;
    let selectedItem = filteredItems[0] ?? null;
    selectedItem?.el.classList.add("selected");
    function handleSearch(cb) {
      filteredItems = cb(items);
      selectedIndex = 0;
      selectedItem?.el.classList.remove("selected");
      selectedItem = filteredItems[selectedIndex];
      selectedItem?.el.classList.add("selected");
    }
    function handleSelected() {
      selectedItem?.onSelect();
    }
    function increaseSelected() {
      if (selectedIndex >= filteredItems.length - 1)
        return;
      selectedIndex += 1;
      selectedItem?.el.classList.remove("selected");
      selectedItem = filteredItems[selectedIndex];
      selectedItem?.el.classList.add("selected");
    }
    function decreaseSelected() {
      if (selectedIndex <= 0)
        return;
      selectedIndex -= 1;
      selectedItem?.el.classList.remove("selected");
      selectedItem = filteredItems[selectedIndex];
      selectedItem?.el.classList.add("selected");
    }
    function dispose() {
      for (const item of filteredItems) {
        item.el.remove();
      }
      selectedItem = null;
    }
    return {
      items,
      getFilteredItems: () => filteredItems,
      handleSearch,
      handleSelected,
      increaseSelected,
      decreaseSelected,
      dispose
    };
  }
  SearchBar.define();

  // src/notif.ts
  function createNotif(text) {
    const element = document.createElement("div");
    element.innerText = text;
    Object.assign(element.style, {
      padding: "4px 8px",
      position: "fixed",
      bottom: 0,
      right: "20px",
      background: "black",
      color: "white",
      borderRadius: "8px 8px 0 0",
      zIndex: 9999,
      border: "1px solid #ffffff",
      borderBottom: "0px solid #ffffff",
      fontFamily: "monospace"
    });
    document.body.appendChild(element);
    return element;
  }
  var notifElement = null;
  function notif(text) {
    if (notifElement) {
      notifElement.innerText = text;
      delayTimeout?.();
      return;
    }
    notifElement = createNotif(text);
    setClearNotif();
  }
  var delayTimeout;
  function setClearNotif() {
    let timeoutId = setTimeout(() => {
      notifElement?.remove();
      notifElement = null;
      delayTimeout = void 0;
    }, 3e3);
    delayTimeout = () => {
      clearTimeout(timeoutId);
      setClearNotif();
    };
  }

  // src/handlers.ts
  var scrollDownABit = () => getScrollable().scrollBy(0, 50);
  var scrollUpABit = () => getScrollable().scrollBy(0, -50);
  var scrollLeftABit = () => getScrollable().scrollBy(-50, 0);
  var scrollRightABit = () => getScrollable().scrollBy(50, 0);
  var scrollDownHalfPage = () => scrollHalfPage("down");
  var scrollUpHalfPage = () => scrollHalfPage("up");
  var scrollToTop = () => getScrollable().scrollTo(0, 0);
  var scrollToBottom = () => handleScrollToBottom();
  var handleResetScrollable = () => resetScrollable();
  var goToNextInput = () => nextInput();
  var insertMode = () => {
    notif("INSERT");
    mode.value = "insert";
  };
  var normalMode = () => {
    notif("NORMAL");
    mode.value = "normal";
  };
  var duplicateTab = () => sendMessage({ type: "duplicateTab" });
  var newTabNextToCurrent = () => sendMessage({ type: "newTabNextToCurrent" });
  var tabsSearch = () => showSearchTabs();

  // src/keymaps.ts
  var normalKeymaps = {
    " ": {
      t: newTabNextToCurrent,
      Tab: tabsSearch
    },
    j: scrollDownABit,
    k: scrollUpABit,
    h: scrollLeftABit,
    l: scrollRightABit,
    d: scrollDownHalfPage,
    u: scrollUpHalfPage,
    f: showLinkTags,
    g: {
      g: scrollToTop,
      i: goToNextInput
    },
    G: scrollToBottom,
    y: {
      t: duplicateTab
    },
    // "M-S-9": handlers.moveTabLeft,
    // "M-S-0": handlers.moveTabRight,
    "'": insertMode,
    Escape: handleResetScrollable
  };
  var normalInputKeymaps = {
    "C-'": insertMode,
    "C-d": scrollDownHalfPage,
    "C-u": scrollUpHalfPage
    // j: {
    //   k: handlers.normalMode,
    // },
  };
  var insertKeymaps = {
    '"': normalMode,
    "C-d": scrollDownHalfPage,
    "C-u": scrollUpHalfPage
    // " ": {
    //   t: handlers.newTabNextToCurrent,
    //   " ": handlers.normalMode,
    //   Tab: handlers.tabsSearch,
    // },
  };
  var insertInputKeymaps = {
    'C-"': normalMode
    // j: {
    //   k: handlers.normalMode,
    // },
  };
  var linksKeymaps = {
    other: clearLinks
  };
  var searchKeymaps = {
    Escape: hideSearchBar
  };
  var alpha = [
    ...Array.from(Array(10)).map((_, i) => i + 48),
    ...Array.from(Array(26)).map((_, i) => i + 65),
    ...Array.from(Array(26)).map((_, i) => i + 97)
  ].map((x) => String.fromCharCode(x));
  alpha.push("Backspace");
  alpha.forEach((char) => linksKeymaps[char] = handleLinkFn(char));
  function getKeymap(event) {
    switch (mode.value) {
      case "normal":
        if (getIsInputTarget(event)) {
          return normalInputKeymaps;
        } else {
          return normalKeymaps;
        }
      case "insert":
        if (getIsInputTarget(event)) {
          log("is insert");
          return insertInputKeymaps;
        } else {
          return insertKeymaps;
        }
      case "links":
        return linksKeymaps;
      case "search":
        return searchKeymaps;
      default:
        const exhaustiveCheck = mode.value;
        throw new Error(`Unhandled getKeymap case: ${exhaustiveCheck}`);
    }
  }
  function getIsInputTarget(event) {
    return event.target !== document.body && ((target) => {
      log("target", target);
      if (!(target instanceof HTMLElement)) {
        return false;
      }
      if (["INPUT", "TEXTAREA"].includes(target.tagName)) {
        return true;
      }
      if (target.getAttribute("contenteditable")) {
        return true;
      }
      return false;
    })(event.composedPath()[0]);
  }

  // src/content.ts
  sendMessage({ type: "greeting", greeting: "hello" }).then(
    (response) => {
      log("Received response: ", response?.farewell);
    }
  );
  var disposeMessageListener = addMessageListener(
    (request, _sender, _sendResponse) => {
      log("Received request: ", request);
    }
  );
  addEventListener("keydown", handleKeyEvent, true);
  var disposeKeydownListener = () => {
    removeEventListener("keydown", handleKeyEvent, true);
  };
  var disposeScrollListener = setupScrollListener();
  function focusHandler() {
    sendMessage({ type: "greeting", greeting: "hello" }).then((response) => {
      if (response)
        return;
      disposeFocusHandler();
      disposeMessageListener();
      disposeKeydownListener();
      disposeScrollListener();
    }).catch((err) => log("err", err));
  }
  window.addEventListener("focus", focusHandler);
  function disposeFocusHandler() {
    window.removeEventListener("focus", focusHandler);
  }
  function handleKeyEvent(event) {
    const key = getKey(event);
    const keymap = getKeymap(event);
    log("key", key, "state", mode.getState(), keymap);
    const mapped = (mode.getState() ?? keymap)[key];
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
      if (getIsInsertInput(event) && event.target instanceof HTMLElement && mode.insertState) {
        event.preventDefault();
        insertText(event.target, mode.insertState);
      }
      mode.setState(null);
      mode.clearInsertState();
    }
  }
  function getIsInsertInput(event) {
    return mode.value === "insert" && getIsInputTarget(event);
  }
})();
