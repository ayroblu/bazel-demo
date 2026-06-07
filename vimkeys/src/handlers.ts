import { mode } from "./mode-helper";
import { nextInput } from "./links-tags";
import {
  getScrollable,
  handleScrollToBottom,
  resetScrollable,
  scrollHalfPage,
} from "./scroll";
import { sendMessage } from "./messaging";
import { showSearchTabs } from "./search-bar";
import { notif } from "./notif.js";

export { clearLinks, showLinkTags, handleLinkFn } from "./links-tags";
export { hideSearchBar } from "./search-bar";

export const scrollDownABit = () => getScrollable().scrollBy(0, 50);
export const scrollUpABit = () => getScrollable().scrollBy(0, -50);
export const scrollLeftABit = () => getScrollable().scrollBy(-50, 0);
export const scrollRightABit = () => getScrollable().scrollBy(50, 0);
export const scrollDownHalfPage = () => scrollHalfPage("down");
export const scrollUpHalfPage = () => scrollHalfPage("up");
export const scrollToTop = () => getScrollable().scrollTo(0, 0);
export const scrollToBottom = () => handleScrollToBottom();
export const handleResetScrollable = () => resetScrollable();
export const goToNextInput = () => nextInput();
export const insertMode = () => {
  notif("INSERT");
  mode.value = "insert";
};
export const normalMode = () => {
  notif("NORMAL");
  mode.value = "normal";
};
export const duplicateTab = () =>
  sendMessage<"duplicateTab">({ type: "duplicateTab" });
export const newTabNextToCurrent = () =>
  sendMessage<"newTabNextToCurrent">({ type: "newTabNextToCurrent" });
export const tabsSearch = () => showSearchTabs();

// Not supported in safari: https://developer.apple.com/documentation/safariservices/safari_web_extensions/assessing_your_safari_web_extension_s_browser_compatibility
// export const bookmarksSearch = () => searchBookmarks("");
// export const moveTabLeft = () =>
//   getCurrentTab().then((tab) => {
//     if (!tab || !tab.id) return;
//     browser.tabs.move(tab.id, { index: tab.index - 1 });
//   });

// export const moveTabRight = () =>
//   getCurrentTab().then((tab) => {
//     if (!tab || !tab.id) return;
//     browser.tabs.move(tab.id, { index: tab.index + 1 });
//   });
