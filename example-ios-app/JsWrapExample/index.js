// Content
console.log('hi', 5 + 5);
console.log(Math.min(5, 4));
console.log("globalThis:", Object.keys(globalThis));
console.log("dict", JSON.stringify(capitalCity));
capitalCity["NZ"] = "Wellington";
console.log("struct", structs, Object.getOwnPropertyNames(globalThis.structs));

now = new Date()

function thing(text) {
  return "got: " + text
}

function subscribe(key, f) {
  f(key, "first")
  console.log(Error("err").stack)
  setTimeout(() => {
    f(key, "later")
  }, 1000);
  key()
}
