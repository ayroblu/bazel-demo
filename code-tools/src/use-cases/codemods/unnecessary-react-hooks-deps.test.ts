import { unnecessaryReactHooksDeps } from "./unnecessary-react-hooks-deps.js";

type Test = {
  name: string;
  input: string;
  expected: string;
  only?: boolean;
};
const tests: Test[] = [
  {
    name: "Should remove hook deps",
    input: `
const value = true;
React.useCallback(() => {
  // blank
}, [value]);
`,
    expected: `
const value = true;
React.useCallback(() => {
  // blank
}, []);
`,
  },
];
describe("unnecessaryReactHooksDeps", () => {
  tests.forEach(({ name, input, expected, only }) => {
    (only ? it.only : it)(name, () => {
      expect(unnecessaryReactHooksDeps(input)).to.equalIgnoreSpaces(expected);
    });
  });
});
