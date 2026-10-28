import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

Widget commentEditor(
        {required quill.QuillController controller,
        required FocusNode focusNode,
        required Widget fallback}) =>
    fallback;
