import { resolveBinaryExpressions } from "./resolve-binary-expressions.js";

type Test = {
  name: string;
  input: string;
  expected: string;
  only?: boolean;
};
const tests: Test[] = [
  {
    name: "should convert boolean true expressions to result",
    input: `
const a = true;
const x = a && b;
`,
    expected: `
const a = true;
const x = b;
`,
  },
  {
    name: "should convert boolean false expressions to no condition",
    input: `
const a = false;
const x = a && b;
`,
    expected: `
const a = false;
const x = false;
`,
  },
  {
    name: "should handle brackets around boolean expressions",
    input: `
const b = true;
const x = a && (d || c);
const y = a && (b || c);
const z = a && b || c;
`,
    expected: `
const b = true;
const x = a && (d || c);
const y = a;
const z = a || c;
`,
  },
  {
    name: "should check ===",
    input: `
const a = true;
const x = a === true;
`,
    expected: `
const a = true;
const x = true;
`,
  },
  {
    name: "should check !==",
    input: `
const a = true;
const x = a !== true;
`,
    expected: `
const a = true;
const x = false;
`,
  },
  {
    name: "should check !",
    input: `
const a = true;
const x = !a;
`,
    expected: `
const a = true;
const x = false;
`,
  },
  {
    name: "should resolve multi || with true or false",
    input: `
const a = true;
const b = false;
const x = A || a || B;
const y = A || b || B;
`,
    expected: `
const a = true;
const b = false;
const x = true;
const y = A || B;
`,
  },
  {
    name: "don't do let",
    input: `
let a = true;
const b = a ? true : false
`,
    expected: `
let a = true;
const b = a ? true : false
`,
  },
];
describe("resolveBinaryExpressions", () => {
  tests.forEach(({ name, input, expected, only }) => {
    (only ? it.only : it)(name, () => {
      expect(resolveBinaryExpressions(input)).to.equalIgnoreSpaces(expected);
    });
  });
});
