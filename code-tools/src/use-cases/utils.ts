export const sortBy = <T>(func: (a: T) => string | number) => {
  return (a: T, b: T) => (func(a) > func(b) ? 1 : func(b) > func(a) ? -1 : 0);
};
export function pred<T>(value: T, f: (v: T) => unknown) {
  return f(value) ? value : undefined;
}
