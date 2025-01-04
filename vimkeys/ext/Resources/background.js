"use strict";
(() => {
  // src/messaging.ts
  function addMessageListener(cb) {
    const callback = cb;
    browser.runtime.onMessage.addListener(callback);
    return () => {
      browser.runtime.onMessage.removeListener(callback);
    };
  }

  // src/background.ts
  addMessageListener((request, sender, sendResponse) => {
    return actions[request.type]?.(request, sender, sendResponse);
  });
  var actions = {
    duplicateTab: (_request, sender, _sendResponse) => {
      if (!sender.tab?.id)
        return;
      browser.tabs.duplicate(sender.tab.id);
    },
    greeting: (request, _sender, sendResponse) => {
      return request.greeting === "hello" ? sendResponse({ farewell: "goodbye" }) : void 0;
    },
    newTabNextToCurrent: (_request, sender, _sendResponse) => {
      const currentIndex = sender.tab?.index;
      if (currentIndex === void 0)
        return;
      browser.tabs.create({ index: currentIndex });
    },
    searchTabs: async (request, _sender, _sendResponse) => {
      const tabs = await browser.tabs.query({});
      const queryParts = request.query.toLowerCase().split(/\s+/g);
      const filteredTabs = tabs.filter(
        (tab) => queryParts.every(
          (queryPart) => tab.title?.includes(queryPart) || tab.url?.includes(queryPart)
        )
      );
      return filteredTabs;
    },
    focusTab: async (request, _sender, _sendResponse) => {
      await browser.tabs.update(request.id, { active: true });
    }
    // searchBookmarks: async (
    //   request: { type: "searchBookmarks"; query: string },
    //   _sender: browser.runtime.MessageSender,
    //   sendResponse: (bookmarks: browser.bookmarks.BookmarkTreeNode[]) => void
    // ) => {
    //   const bookmarks = await browser.bookmarks.search(request.query);
    //   sendResponse(bookmarks);
    // },
  };
})();
