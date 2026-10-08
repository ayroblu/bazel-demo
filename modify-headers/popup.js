const rowsEl = document.getElementById("rows");
const previewEl = document.getElementById("preview");

let headers = [];
let draggedIndex = null;
let rowDefaults = { operation: "set", delimiter: ", " };
let domains = defaultDomains();

const domainsDialog = document.getElementById("domains-dialog");
const domainError = document.getElementById("domain-error");

function newRow() {
  return { enabled: true, ...rowDefaults, name: "", value: "" };
}

function save() {
  renderPreview();
  chrome.storage.local.set({ headers, rowDefaults });
}

function renderPreview() {
  previewEl.textContent =
    (domains.some((domain) => domain.enabled) ? buildRequestHeaders(headers) : [])
      .map(({ header, operation, value }) =>
        operation === "remove" ? `${header}: (removed)` : `${header}: ${value}`
      )
      .join("\n") || "(disabled)";
}

function render() {
  rowsEl.replaceChildren(
    ...headers.map((header, index) => {
      const row = document.createElement("div");
      row.className = "row";
      const handle = dragHandle(row, index);
      const remove = document.createElement("button");
      remove.textContent = "✕";
      remove.title = "Remove row";
      remove.onclick = () => {
        headers.splice(index, 1);
        render();
        save();
      };

      if (header.type === "section") {
        row.classList.add("section");
        const title = textInput("section-title", header.title, (text) => (header.title = text));
        title.placeholder = "Section title";
        row.append(handle, document.createElement("hr"), title, document.createElement("hr"), remove);
        return row;
      }

      const enabled = document.createElement("input");
      enabled.type = "checkbox";
      enabled.checked = header.enabled;
      enabled.onchange = () => {
        header.enabled = enabled.checked;
        save();
      };

      const operation = document.createElement("select");
      operation.append(
        ...["set", "add", "remove"].map((op) => new Option(op, op, false, op === header.operation))
      );
      operation.onchange = () => {
        header.operation = operation.value;
        rowDefaults.operation = operation.value;
        updateVisibility();
        save();
      };

      const name = textInput("name", header.name, (text) => (header.name = text));
      name.placeholder = "Header name";
      const value = textInput("value", header.value, (text) => (header.value = text));
      value.placeholder = "Header value";
      const delimiter = textInput("delimiter", header.delimiter, (text) => {
        header.delimiter = text;
        rowDefaults.delimiter = text;
      });
      delimiter.title = "Delimiter used to join values for this header";

      function updateVisibility() {
        value.style.visibility = header.operation === "remove" ? "hidden" : "";
        delimiter.style.visibility = header.operation === "add" ? "" : "hidden";
      }
      updateVisibility();

      row.append(handle, enabled, operation, name, value, delimiter, remove);
      return row;
    })
  );
  rowsEl.querySelectorAll("textarea").forEach(resizeTextArea);
}

document.getElementById("add").onclick = () => {
  headers.push(newRow());
  render();
  save();
  rowsEl.lastChild.querySelector(".value").focus();
};

document.getElementById("add-section").onclick = () => {
  headers.push({ type: "section", title: "" });
  render();
  save();
  rowsEl.lastChild.querySelector(".section-title").focus();
};

document.getElementById("edit-domains").onclick = () => {
  renderDomains();
  domainError.hidden = true;
  domainsDialog.showModal();
};

document.getElementById("close-domains").onclick = () => domainsDialog.close();

document.getElementById("add-domain").onsubmit = async (event) => {
  event.preventDefault();
  const input = document.getElementById("domain-name");
  const name = input.value.trim().toLowerCase();
  domainError.hidden = true;
  if (name !== "*" && (!/^(?=.{1,253}$)[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*$/.test(name) ||
      name.split(".").some((label) => label.length > 63))) {
    showDomainError("Enter a domain name such as example.com, or * for all sites.");
    return;
  }
  if (domains.some((domain) => domain.name === name)) {
    showDomainError("This domain is already listed.");
    return;
  }
  if (!(await requestDomainPermission(name))) return;
  domains.push({ name, enabled: true });
  await saveDomains();
  renderDomains();
  input.value = "";
  input.focus();
};

chrome.storage.local.get(["headers", "rowDefaults", "domains"]).then((stored) => {
  rowDefaults = { ...rowDefaults, ...stored.rowDefaults };
  headers = stored.headers?.length ? stored.headers : [newRow()];
  domains = stored.domains ?? domains;
  render();
  renderPreview();
});

function renderDomains() {
  document.getElementById("domain-rows").replaceChildren(
    ...domains.map((domain, index) => {
      const row = document.createElement("div");
      row.className = "domain-row";
      const enabled = document.createElement("input");
      enabled.type = "checkbox";
      enabled.checked = domain.enabled;
      enabled.onchange = async () => {
        domainError.hidden = true;
        enabled.disabled = true;
        if (enabled.checked && !(await requestDomainPermission(domain.name))) {
          enabled.checked = false;
          enabled.disabled = false;
          return;
        }
        domain.enabled = enabled.checked;
        await saveDomains();
        enabled.disabled = false;
      };
      const label = document.createElement("label");
      label.append(enabled, document.createTextNode(domain.name));
      const remove = document.createElement("button");
      remove.textContent = "✕";
      remove.title = `Remove ${domain.name}`;
      remove.onclick = () => {
        domains.splice(index, 1);
        saveDomains();
        renderDomains();
      };
      row.append(label, remove);
      return row;
    })
  );
}

async function requestDomainPermission(name) {
  try {
    const granted = await chrome.permissions.request({ origins: [domainPermission(name)] });
    if (!granted) showDomainError("Permission was declined. The domain remains disabled.");
    return granted;
  } catch (error) {
    showDomainError(error.message);
    return false;
  }
}

function saveDomains() {
  renderPreview();
  return chrome.storage.local.set({ domains });
}

function showDomainError(message) {
  domainError.textContent = message;
  domainError.hidden = false;
}

function dragHandle(row, index) {
  const handle = document.createElement("span");
  handle.className = "drag-handle";
  handle.textContent = "⠿";
  handle.title = "Drag to reorder row";
  handle.draggable = true;
  handle.ondragstart = (event) => {
    draggedIndex = index;
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", String(index));
    event.dataTransfer.setDragImage(row, 0, 0);
    row.classList.add("dragging");
  };
  handle.ondragend = () => {
    draggedIndex = null;
    clearDragStyles();
  };
  row.ondragover = (event) => {
    if (draggedIndex === null) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";
    clearDragStyles();
    const bounds = row.getBoundingClientRect();
    row.classList.add(event.clientY < bounds.top + bounds.height / 2 ? "drop-before" : "drop-after");
  };
  row.ondragleave = () => {
    row.classList.remove("drop-before", "drop-after");
  };
  row.ondrop = (event) => {
    if (draggedIndex === null) return;
    event.preventDefault();
    const bounds = row.getBoundingClientRect();
    let destination = index + (event.clientY >= bounds.top + bounds.height / 2 ? 1 : 0);
    if (draggedIndex < destination) destination--;
    const [moved] = headers.splice(draggedIndex, 1);
    headers.splice(destination, 0, moved);
    draggedIndex = null;
    render();
    save();
  };
  return handle;
}

function clearDragStyles() {
  for (const row of rowsEl.children) {
    row.classList.remove("dragging", "drop-before", "drop-after");
  }
}

function textInput(className, initial, onInput) {
  const multiline = className === "name" || className === "value";
  const input = document.createElement(multiline ? "textarea" : "input");
  if (multiline) {
    input.rows = 1;
    input.onkeydown = (event) => {
      if (event.key === "Enter") event.preventDefault();
    };
  } else {
    input.type = "text";
  }
  input.className = className;
  input.value = initial;
  input.oninput = () => {
    if (multiline) {
      input.value = input.value.replace(/[\r\n]/g, "");
      resizeTextArea(input);
    }
    onInput(input.value);
    save();
  };
  return input;
}

function resizeTextArea(input) {
  input.style.height = "auto";
  input.style.height = `${input.scrollHeight + input.offsetHeight - input.clientHeight}px`;
}
