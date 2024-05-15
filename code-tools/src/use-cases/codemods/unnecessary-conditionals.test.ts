import { unnecessaryConditionals } from "./unnecessary-conditionals.js";

type Test = {
  name: string;
  input: string;
  expected: string;
  only?: boolean;
};
const tests: Test[] = [
  {
    name: "Should remove if statement directly true",
    input: `
if (true) {
  console.log(a);
}
`,
    expected: `
console.log(a);
`,
  },
  {
    name: "Should remove if statement without block when directly true",
    input: `
if (true) console.log(a);
`,
    expected: `
console.log(a);
`,
  },
  {
    name: "Should remove if contents if directly false",
    input: `
if (false) {
  console.log(a);
}
`,
    expected: `
`,
  },
  {
    name: "Should remove if statement if constant is truthy",
    input: `
const a = true;
if (a) {
  console.log(a);
}
`,
    expected: `
const a = true;
console.log(a);
`,
  },
  {
    name: "Should remove ternary if constant is truthy",
    input: `
const a = true;
const b = a ? 1 : 2;
`,
    expected: `
const a = true;
const b = 1;
`,
  },
  {
    name: "Should remove if statement but keep block if shadows variable",
    input: `
const a = true;
if (a) {
  const a = false;
}
`,
    expected: `
const a = true;
{
  const a = false;
}
`,
  },
  {
    name: "Should keep else side only if false",
    input: `
const a = false;
if (a) {
  console.log(true);
} else {
  console.log(false);
}
`,
    expected: `
const a = false;
console.log(false);
`,
  },
  {
    name: "Should keep else if and else side only if false",
    input: `
const a = false;
if (a) {
  console.log(true);
} else if (window) {
  console.log(window);
} else {
  console.log(false);
}
`,
    expected: `
const a = false;
if (window) {
  console.log(window);
} else {
  console.log(false);
}
`,
  },
  {
    name: "Should do nothing if mutable and unclear",
    input: `
const a = { state: true };
doSomething(a);
if (a.state) {
  console.log(a);
}
`,
    expected: `
const a = { state: true };
doSomething(a);
if (a.state) {
  console.log(a);
}
`,
  },
  {
    name: "Should follow refs",
    input: `
function run(a: boolean) {
  if (a) {
    console.log(true);
  }
}
run(true);
`,
    expected: `
function run(a: boolean) {
  console.log(true);
}
run(true);
`,
  },
  {
    name: "Should follow refs to declarations",
    input: `
function run(a: boolean) {
  if (a) {
    console.log(true);
  }
}
const c = true;
run(c);
`,
    expected: `
function run(a: boolean) {
  console.log(true);
}
const c = true;
run(c);
`,
  },
  {
    name: "Should resolve default arguments with no references as value",
    input: `
function run(a: boolean = true) {
  if (a) {
    console.log(true);
  }
}
run();
`,
    expected: `
function run(a: boolean = true) {
  console.log(true);
}
run();
`,
  },
  {
    name: "Should resolve default arguments for arrow functions with no references as value",
    input: `
const run = (a: boolean = true) => {
  if (a) {
    console.log(true);
  }
}
run();
`,
    expected: `
const run = (a: boolean = true) => {
  console.log(true);
}
run();
`,
  },
  {
    name: "should not resolve conditions when functions are exported",
    input: `
export function run(a: boolean = true) {
  if (a) {
    console.log(true);
  }
}
`,
    expected: `
export function run(a: boolean = true) {
  if (a) {
    console.log(true);
  }
}
`,
  },
];
describe("unnecessaryConditionals", () => {
  tests.forEach(({ name, input, expected, only }) => {
    (only ? it.only : it)(name, () => {
      expect(unnecessaryConditionals(input)).to.equalIgnoreSpaces(expected);
    });
  });
});
