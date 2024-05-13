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
  const extensions = [".js"];
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
  for (const filePath of filePaths) {
    const source = readFileSync(filePath, { encoding: "utf8" });
    let result = source;
    for (const [before, after] of entries) {
      if (!source.includes(before)) {
        continue;
      }
      const query = {
        type: ["jsx_self_closing_element", "jsx_opening_element"],
        items: [
          {
            field: "name",
            text: /^(View|Image|Button|Icon\w+)$/,
          },
          {
            type: "jsx_attribute",
            items: [
              {
                type: "property_identifier",
                capture: "identifier",
                text: before,
              },
            ],
          },
        ],
      } as const;

      const tree = parser.parse(result);
      const edits: CodeEdit[] = [];
      const traverseQuery = buildTraverseQuery(query, (captures) => {
        edits.push({
          startIndex: captures.identifier.startIndex,
          endIndex: captures.identifier.endIndex,
          newText: after,
        });
        return { skip: true };
      });
      traverseWithCursor(tree.walk(), traverseQuery);
      result = runEdits(result, edits);
    }
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
