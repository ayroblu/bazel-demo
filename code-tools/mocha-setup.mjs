import * as chai from "chai";
import chaiString from "chai-string";

const { expect } = chai.use(chaiString);
// see: "chai/register-expect.js",
globalThis.expect = expect;

