import { Keymap } from "./types";
import * as handlers from "./handlers";
import { log } from "./log";
import { mode } from "./mode-helper";

// to handle p + pa, we need to add a "default" option
const normalKeymaps: Keymap = {
  " ": {
    t: handlers.newTabNextToCurrent,
    Tab: handlers.tabsSearch,
  },
  j: handlers.scrollDownABit,
  k: handlers.scrollUpABit,
  h: handlers.scrollLeftABit,
  l: handlers.scrollRightABit,
  d: handlers.scrollDownHalfPage,
  u: handlers.scrollUpHalfPage,
  f: handlers.showLinkTags,
  g: {
    g: handlers.scrollToTop,
    i: handlers.goToNextInput,
  },
  G: handlers.scrollToBottom,
  y: {
    t: handlers.duplicateTab,
  },
  // "M-S-9": handlers.moveTabLeft,
  // "M-S-0": handlers.moveTabRight,
  "'": handlers.insertMode,
  Escape: handlers.handleResetScrollable,
};
const normalInputKeymaps: Keymap = {
  "C-'": handlers.insertMode,
  "C-d": handlers.scrollDownHalfPage,
  "C-u": handlers.scrollUpHalfPage,
  // j: {
  //   k: handlers.normalMode,
  // },
};
const insertKeymaps: Keymap = {
  '"': handlers.normalMode,
  "C-d": handlers.scrollDownHalfPage,
  "C-u": handlers.scrollUpHalfPage,
  // " ": {
  //   t: handlers.newTabNextToCurrent,
  //   " ": handlers.normalMode,
  //   Tab: handlers.tabsSearch,
  // },
};
const insertInputKeymaps: Keymap = {
  'C-"': handlers.normalMode,
  // j: {
  //   k: handlers.normalMode,
  // },
};
const linksKeymaps: Keymap = {
  other: handlers.clearLinks,
};
const searchKeymaps: Keymap = {
  Escape: handlers.hideSearchBar,
};
const alpha = [
  ...Array.from(Array(10)).map((_, i) => i + 48),
  ...Array.from(Array(26)).map((_, i) => i + 65),
  ...Array.from(Array(26)).map((_, i) => i + 97),
].map((x) => String.fromCharCode(x));
alpha.push("Backspace");
alpha.forEach((char) => (linksKeymaps[char] = handlers.handleLinkFn(char)));

export function getKeymap(event: KeyboardEvent): Keymap {
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
      const exhaustiveCheck: never = mode.value;
      throw new Error(`Unhandled getKeymap case: ${exhaustiveCheck}`);
  }
}

export function getIsInputTarget(event: KeyboardEvent) {
  return (
    event.target !== document.body &&
    ((target: EventTarget | null) => {
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
      // if (["A", "BUTTON", "DIV"].includes(target.tagName)) {
      //   return false;
      // }
      // if (target.tabIndex === -1) {
      //   return false;
      // }
      // if (target.tabIndex >= 0) {
      //   return false;
      // }
      return false;
    })(event.composedPath()[0])
  );
}
