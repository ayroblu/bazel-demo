const { print_and_add } = require('../example-wasm');

test("printAndAdd returns 3", async () => {
  expect(print_and_add(1,2)).toBe(3);
});
