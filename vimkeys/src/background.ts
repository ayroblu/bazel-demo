import { addMessageListener } from "./messaging";

// Message listener disposal appears to be handled automatically in background.ts?
addMessageListener((request, sender, sendResponse) => {
  return actions[request.type]?.(request as any, sender, sendResponse as any);
});

const actions = {
  duplicateTab: (
    _request: { type: "duplicateTab" },
    sender: browser.runtime.MessageSender,
    _sendResponse: () => void
  ) => {
    if (!sender.tab?.id) return;
    browser.tabs.duplicate(sender.tab.id);
  },
  greeting: (
    request: { type: "greeting"; greeting: string },
    _sender: browser.runtime.MessageSender,
    sendResponse: (resp: { farewell: string }) => void
  ) => {
    return request.greeting === "hello"
      ? sendResponse({ farewell: "goodbye" })
      : undefined;
  },
  newTabNextToCurrent: (
    _request: { type: "newTabNextToCurrent" },
    sender: browser.runtime.MessageSender,
    _sendResponse: () => void
  ) => {
    const currentIndex = sender.tab?.index;
    if (currentIndex === undefined) return;
    browser.tabs.create({ index: currentIndex });
  },
  searchTabs: async (
    request: { type: "searchTabs"; query: string },
    _sender: browser.runtime.MessageSender,
    _sendResponse: (tabs: browser.tabs.Tab[]) => void
  ) => {
    const tabs = await browser.tabs.query({});
    const queryParts = request.query.toLowerCase().split(/\s+/g);
    const filteredTabs = tabs.filter((tab) =>
      queryParts.every(
        (queryPart) =>
          tab.title?.includes(queryPart) || tab.url?.includes(queryPart)
      )
    );
    return filteredTabs;
  },
  focusTab: async (
    request: { type: "focusTab"; id: number },
    _sender: browser.runtime.MessageSender,
    _sendResponse: (tabs: browser.tabs.Tab[]) => void
  ) => {
    await browser.tabs.update(request.id, { active: true });
  },
  // searchBookmarks: async (
  //   request: { type: "searchBookmarks"; query: string },
  //   _sender: browser.runtime.MessageSender,
  //   sendResponse: (bookmarks: browser.bookmarks.BookmarkTreeNode[]) => void
  // ) => {
  //   const bookmarks = await browser.bookmarks.search(request.query);
  //   sendResponse(bookmarks);
  // },
};

export type Actions = typeof actions;
export type MessageListener<K extends keyof Actions> = (
  request: Parameters<Actions[K]>[0],
  sender: browser.runtime.MessageSender,
  sendResponse: Parameters<Actions[K]>[2]
) => void;
