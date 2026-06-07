export function collect<T, R>(
  arr: T[],
  fn: (item: T) => R | undefined | null
): R[] {
  if (!arr.length) {
    return [];
  }
  return arr.reduce<R[]>((newArr, next) => {
    const result = fn(next);
    if (result !== null && result !== undefined) {
      newArr.push(result);
    }
    return newArr;
  }, []);
}

export function getKey(event: KeyboardEvent) {
  return (
    [
      event.ctrlKey ? "C-" : null,
      event.metaKey ? "M-" : null,
      event.altKey ? "A-" : null,
      event.shiftKey && (event.ctrlKey || event.metaKey || event.altKey)
        ? "S-"
        : null,
    ]
      .filter(Boolean)
      .join("") + event.key
  );
}
