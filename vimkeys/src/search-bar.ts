import { log } from "./log.js";
import { sendMessage } from "./messaging";
import { mode } from "./mode-helper";
import { collect, getKey } from "./utils";

let mountedBar: SearchBar | null = null;
export async function showSearchTabs() {
  const searchBar = getSearchBar();
  const tabs = await sendMessage<"searchTabs">({
    type: "searchTabs",
    query: "",
  });
  const items = collect(tabs, ({ id, title, url }) =>
    title && id !== undefined
      ? {
          id: id + "",
          onSelect: () => sendMessage({ type: "focusTab", id }),
          title,
          subtitle: url,
        }
      : null
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
function createSearchBar(): SearchBar {
  const el = SearchBar.create();
  document.body.appendChild(el);
  return el;
}
export function hideSearchBar() {
  if (!mountedBar) return;
  mountedBar.hide();
  mode.value = "normal";
}

class CustomElement extends HTMLElement {
  static elementName = "placeholder";
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
  static create<T extends CustomElement>(
    this: { new (): T } & typeof CustomElement
  ): T {
    const name = this.elementName;
    return document.createElement(name) as T;
  }

  constructor() {
    super();
    if (this.constructor == CustomElement) {
      throw new Error("Abstract class CustomElement can't be instantiated.");
    }
  }
}

class SearchBar extends CustomElement {
  static elementName = "vimkey-seach-bar";
  container: HTMLElement | null = null;
  input: HTMLInputElement | null = null;
  list: HTMLElement | null = null;

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
  handleSearch = () => {
    if (!this.input) return;
    const query = this.input.value;

    this.items?.handleSearch((items) => {
      const queryParts = query.toLowerCase().split(/\s+/g);
      const filteredItems = items.reduce<ItemWithEl[]>((list, item) => {
        const isVisible = queryParts.every(
          (queryPart) =>
            item.title?.includes(queryPart) ||
            item.subtitle?.includes(queryPart)
        );
        if (isVisible) {
          list.push(item);
          this.list!.appendChild(item.el);
        } else {
          item.el.remove();
        }
        return list;
      }, []);
      return filteredItems;
    });
  };
  handleKeydown = (event: KeyboardEvent) => {
    if (!this.list) return;
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
  hide = () => {
    const container = this.container;
    if (!container) return;
    container.style.display = "none";
    mode.value = "normal";
  };
  show = () => {
    const container = this.container;
    if (!container) return;
    const input = this.input;
    input!.focus();
    input!.value = "";
    const list = this.list;
    list!.innerHTML = "";
    container.style.display = "flex";
    if (!this.input) return;
    this.input.oninput = this.handleSearch;
    this.input.onkeydown = this.handleKeydown;
  };
  items: ReturnType<typeof itemsFilterFn<ItemWithEl>> | null = null;
  setItems = (items: Item[]) => {
    const list = this.list;
    if (!list) return;
    list.innerHTML = "";
    const itemsWithEl = items.map((item) => {
      const el: HTMLElement = document.createElement("div");
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
        el,
      };
    });
    this.items?.dispose();
    this.items = itemsFilterFn(itemsWithEl);
  };
}
type Item = {
  onSelect: () => void;
  id: string;
  title: string;
  subtitle?: string;
};
type ItemWithEl = Item & { el: HTMLElement };

function itemsFilterFn<T extends { onSelect: () => void; el: HTMLElement }>(
  items: T[]
) {
  let filteredItems = items;
  let selectedIndex = 0;
  let selectedItem: null | T = filteredItems[0] ?? null;
  selectedItem?.el.classList.add("selected");

  function handleSearch(cb: (items: T[]) => T[]) {
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
    if (selectedIndex >= filteredItems.length - 1) return;
    selectedIndex += 1;
    selectedItem?.el.classList.remove("selected");
    selectedItem = filteredItems[selectedIndex];
    selectedItem?.el.classList.add("selected");
  }
  function decreaseSelected() {
    if (selectedIndex <= 0) return;
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
    dispose,
  };
}

SearchBar.define();
