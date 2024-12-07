// Setup
const originalLog = console.log
console.log = function(...args) {
  originalLog(args.join(" "))
}

// Content
console.log('hi', 5 + 5);
console.log(5 + 5);
console.log(Math.min(5, 4));
console.log("globalThis:", Object.keys(globalThis));
thing = new Date()
function subscribe(key, f) {
  console.log(Object.getOwnPropertyNames(globalThis.hi));
  f(key, "first")
  console.log(setTimeout);
  setTimeout(() => {
    f(key, "later")
  }, 1000);
}
