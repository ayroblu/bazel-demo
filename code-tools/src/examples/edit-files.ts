import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { isMainScript } from "../misc-utils.js";
import { shell } from "./utils/shell.js";
import Parser from "tree-sitter";
import ts from "tree-sitter-typescript";
import { buildTraverseQuery } from "../query.js";
import { traverseWithCursor } from "../traverse.js";
import { runEdits, type CodeEdit } from "../codemod.js";
const { tsx } = ts;

const parser = new Parser();
parser.setLanguage(tsx);

if (isMainScript(import.meta.url)) {
  const { stdout: gitFilesOutput } = await shell("git ls-files $DIRECTORY", {
    env: { DIRECTORY: "." },
  });
  const extensions = [".js", ".flow"];
  const filePaths = gitFilesOutput
    .split("\n")
    .filter(
      (filePath) =>
        filePath &&
        extensions.some((extension) => filePath.endsWith(extension)) &&
        existsSync(filePath),
    );

  const maps = getMaps();
  const entries = Object.entries(maps);
  const map = new Map(entries);
  for (const filePath of filePaths) {
    const source = readFileSync(filePath, { encoding: "utf8" });
    let result = source;
    const query = {
      type: [
        "string_fragment",
        "identifier",
        "property_identifier",
        "type_identifier",
        "shorthand_property_identifier",
        "shorthand_property_identifier_pattern",
      ],
      capture: "str",
    } as const;

    const edits: CodeEdit[] = [];
    const traverseQuery = buildTraverseQuery(query, (captures) => {
      let mapped = map.get(captures.str.text);
      if (mapped) {
        let startOffset = 0;
        switch (captures.str.type) {
          case "identifier":
            mapped = mapped.replace(/-(\w)/g, (_, char) => char.toUpperCase());
            break;
          case "shorthand_property_identifier":
          case "shorthand_property_identifier_pattern": {
            const camelCase = mapped.replace(/-(\w)/g, (_, char) =>
              char.toUpperCase(),
            );
            mapped = `'${mapped}': ${camelCase}`;
            break;
          }
          case "type_identifier":
            mapped = `'${mapped}'`;
            break;
          case "property_identifier":
            const parentType = captures.str.parent?.type;
            if (!parentType) break;
            switch (parentType) {
              case "member_expression":
                mapped = `['${mapped}']`;
                startOffset = -1;
                break;
              case "pair":
              case "property_signature":
                mapped = `'${mapped}'`;
                break;
            }
            break;
        }
        edits.push({
          startIndex: captures.str.startIndex + startOffset,
          endIndex: captures.str.endIndex,
          newText: mapped,
        });
      }
      return { skip: true };
    });
    const tree = parser.parse(result);
    traverseWithCursor(tree.walk(), traverseQuery);
    result = runEdits(result, edits);
    if (source !== result) {
      writeFileSync(filePath, result);
    }
  }
}

function getMaps() {
  return {
    accessibilityDisabled: "aria-disabled",
    accessibilityActiveDescendant: `aria-activedescendant`,
    accessibilityAtomic: `aria-atomic`,
    accessibilityAutoComplete: `aria-autocomplete`,
    accessibilityBusy: `aria-busy`,
    accessibilityChecked: `aria-checked`,
    accessibilityColumnCount: `aria-colcount`,
    accessibilityColumnIndex: `aria-colindex`,
    accessibilityColumnSpan: `aria-colspan`,
    accessibilityControls: `aria-controls`,
    accessibilityCurrent: `aria-current`,
    accessibilityDescribedBy: `aria-describedby`,
    accessibilityDetails: `aria-details`,
    accessibilityErrorMessage: `aria-errormessage`,
    accessibilityExpanded: `aria-expanded`,
    accessibilityFlowTo: `aria-flowto`,
    accessibilityHasPopup: `aria-haspopup`,
    accessibilityHidden: `aria-hidden`,
    accessibilityInvalid: `aria-invalid`,
    accessibilityKeyShortcuts: `aria-keyshortcuts`,
    accessibilityLabel: `aria-label`,
    accessibilityLabelledBy: `aria-labelledby`,
    accessibilityLevel: `aria-level`,
    accessibilityLiveRegion: `aria-live`,
    accessibilityModal: `aria-modal`,
    accessibilityMultiline: `aria-multiline`,
    accessibilityMultiSelectable: `aria-multiselectable`,
    accessibilityOrientation: `aria-orientation`,
    accessibilityOwns: `aria-owns`,
    accessibilityPlaceholder: `aria-placeholder`,
    accessibilityPosInSet: `aria-posinset`,
    accessibilityPressed: `aria-pressed`,
    accessibilityReadOnly: `aria-readonly`,
    accessibilityRequired: `aria-required`,
    accessibilityRole: `role`,
    accessibilityRoleDescription: `aria-roledescription`,
    accessibilityRowCount: `aria-rowcount`,
    accessibilityRowIndex: `aria-rowindex`,
    accessibilityRowSpan: `aria-rowspan`,
    accessibilitySelected: `aria-selected`,
    accessibilitySetSize: `aria-setsize`,
    accessibilitySort: `aria-sort`,
    accessibilityValueMax: `aria-valuemax`,
    accessibilityValueMin: `aria-valuemin`,
    accessibilityValueNow: `aria-valuenow`,
    accessibilityValueText: `aria-valuetext`,
    nativeID: `id`,
  };
}

// pointerEvents: `style.pointerEvents`,
// 743:      `focusable is deprecated.`);
// tabindex
