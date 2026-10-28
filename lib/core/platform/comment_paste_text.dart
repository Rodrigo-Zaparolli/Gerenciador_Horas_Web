/// Quill documents require LF line endings; Windows clipboard uses CRLF.
String normalizeCommentPastedText(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
