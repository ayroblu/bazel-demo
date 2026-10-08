function buildRequestHeaders(rows) {
  const grouped = new Map();
  for (const row of rows) {
    if (row.type === "section") continue;
    const name = row.name.trim();
    if (!row.enabled || !name) continue;
    const key = name.toLowerCase();
    if (row.operation === "remove") {
      grouped.set(key, { header: name, operation: "remove" });
      continue;
    }
    const value = trimValue(row);
    if (!value) continue;
    const current = grouped.get(key);
    grouped.set(key, {
      header: name,
      operation: "set",
      value:
        row.operation === "add" && current?.value ? current.value + row.delimiter + value : value,
    });
  }
  return [...grouped.values()];
}

function trimValue({ operation, value, delimiter }) {
  let trimmed = value.trim();
  const trimmedDelimiter = delimiter.trim();
  if (operation === "add" && trimmedDelimiter) {
    while (trimmed.endsWith(trimmedDelimiter)) {
      trimmed = trimmed.slice(0, -trimmedDelimiter.length).trimEnd();
    }
  }
  return trimmed;
}
