export function createCacheManager<T>() {
  const cache = new Map<string, { value: T }>();
  function get(key: string, getter: () => T) {
    const cachedValue = cache.get(key);
    if (cachedValue) {
      return cachedValue.value;
    }
    const result = getter();
    cache.set(key, { value: result });
    return result;
  }
  return {
    get,
  };
}
