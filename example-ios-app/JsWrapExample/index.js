// Content
console.log('hi', 5 + 5);
console.log(5 + 5);
console.log(Math.min(5, 4));
console.log("globalThis:", Object.keys(globalThis));
thing = new Date()
function subscribe(key, f) {
  f(key, "first")
  console.log(Error("err").stack)
  setTimeout(() => {
    f(key, "later")
  }, 1000);
  key()
}
