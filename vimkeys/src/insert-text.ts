export function insertText(textField: HTMLElement, text: string): void {
  if (
    textField instanceof HTMLInputElement ||
    textField instanceof HTMLTextAreaElement
  ) {
    if (textField.selectionStart || textField.selectionStart === 0) {
      const startPos = textField.selectionStart;
      const endPos = textField.selectionEnd;
      textField.value =
        textField.value.substring(0, startPos) +
        text +
        (endPos
          ? textField.value.substring(endPos, textField.value.length)
          : "");
    } else {
      textField.value += text;
    }
  } else {
    insertTextAtCaretContentEditable(text);
  }
}
// https://stackoverflow.com/questions/2920150/insert-text-at-cursor-in-a-content-editable-div
function insertTextAtCaretContentEditable(text: string) {
  if (window.getSelection) {
    const sel = window.getSelection();
    if (sel && sel.getRangeAt && sel.rangeCount) {
      const range = sel.getRangeAt(0);
      range.deleteContents();
      range.insertNode(document.createTextNode(text));
    }
    // } else if (document.selection && document.selection.createRange) {
    //     document.selection.createRange().text = text;
  }
}
