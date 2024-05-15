import { unusedVariables } from "./unused-vars.js";

type Test = {
  name: string;
  input: string;
  expected: string;
  only?: boolean;
  skip?: boolean;
};
const tests: Test[] = [
  {
    name: "should remove b when unused lexical_declaration",
    input: `
const a = 1;
const b = 1;
console.log(a);
`,
    expected: `
const a = 1;
console.log(a);
`,
  },
  {
    name: "should remove b and c when subsequent variable_declarator",
    input: `
const a = 1, b = 2, c = 3;
console.log(a);
`,
    expected: `
const a = 1;
console.log(a);
`,
  },
  {
    name: "should remove b, c when unused lexical_declaration",
    input: `
const a = 1;
const b = 1, c = 1;
console.log(a);
`,
    expected: `
const a = 1;
console.log(a);
`,
  },
  {
    name: "should remove outer a",
    input: `
const a = 1;
function run() {
  const a = 1;
  console.log(a);
}
`,
    expected: `
function run() {
  const a = 1;
  console.log(a);
}
`,
  },
  {
    name: "should handle used for_statement initializers reasonably",
    input: `
for (let i = 0; i < 5; ++i) {
  console.log(i);
}
`,
    expected: `
for (let i = 0; i < 5; ++i) {
  console.log(i);
}
`,
  },
  {
    name: "should handle unused for_statement variable_declarator",
    input: `
for (let i = 0, b = 0; i < 5; ++i) {
  console.log(i);
}
`,
    expected: `
for (let i = 0; i < 5; ++i) {
  console.log(i);
}
`,
  },
  {
    name: "should handle unused for_statement initializers reasonably",
    input: `
for (let i = 0;;) {
  break;
}
`,
    expected: `
for (let i = 0;;) {
  break;
}
`,
    skip: true,
  },
  {
    name: "should handle unused for_statement of initializers reasonably",
    input: `
for (const a of loop) {
  break;
}
`,
    expected: `
for (const a of loop) {
  break;
}
`,
  },
  {
    name: "should ignore exported statements",
    input: `
const a = 1;
export const b = 2
const c = 3
export default a;
`,
    expected: `
const a = 1;
export const b = 2
export default a;
`,
  },
];
describe("unusedVariables", () => {
  tests.forEach(({ only, name, input, expected, skip }) => {
    (only ? it.only : skip ? it.skip : it)(name, () => {
      expect(unusedVariables(input)).to.equalIgnoreSpaces(expected);
    });
  });
});
