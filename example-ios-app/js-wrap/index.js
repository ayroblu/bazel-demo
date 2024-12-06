// Setup
const originalLog = console.log
console.log = function(...args) {
  originalLog(args)
}

// Content
console.log('hi', 5 + 5);
console.log(5 + 5);
thing = new Date()
