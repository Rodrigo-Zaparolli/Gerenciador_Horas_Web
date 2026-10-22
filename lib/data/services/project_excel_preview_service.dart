import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:gerenciador_horas/data/services/project_storage_service.dart';
import 'browser_local_files_service.dart';
import 'native_local_files_service.dart';

typedef NativeExcelRequest = Future<Map<String, dynamic>>
    Function(String action, {String? reference, String? name, String? range});

class ProjectExcelPreviewService {
  ProjectExcelPreviewService({
    ProjectStorageService? storageService,
    NativeExcelRequest? nativeRequest,
    String? projectId,
  })  : _storageService = storageService,
        _nativeRequest = nativeRequest ??
            ((String action,
                    {String? reference, String? name, String? range}) =>
                NativeLocalFiles.call(action,
                    reference: reference,
                    name: name,
                    range: range,
                    projectId: projectId,
                    projectField: 'excelLink'));

  static const int _maxRows = 40;
  static const int _maxColumns = 20;
  static const int _maxCells = 600;
  static const double _maxImageWidth = 1000;
  static const double _maxImageHeight = 1000;

  final ProjectStorageService? _storageService;
  final NativeExcelRequest _nativeRequest;

  Future<String> renderRangeAsBase64({
    required String fileReference,
    required String rangeReference,
    bool preserveLayout = false,
  }) async {
    if (preserveLayout) {
      final result = await _nativeRequest('preview',
          reference: fileReference, range: rangeReference);
      if (result['cancelled'] == true) {
        throw const NativeFilesException(
            'Selecione a planilha original para gerar o espelho.');
      }
      final image = result['imagemBase64'];
      if (result['renderer'] != 'excel' || image is! String || image.isEmpty) {
        throw const NativeFilesException(
            'A integração respondeu, mas não gerou a imagem do Excel. Tente novamente e confira a planilha e o intervalo selecionados.');
      }
      return image;
    }
    final bytes = BrowserLocalFiles.isReference(fileReference)
        ? await BrowserLocalFiles.read(fileReference)
        : await (_storageService ?? ProjectStorageService())
            .downloadBytes(fileReference);
    return renderBytesAsBase64(bytes: bytes, rangeReference: rangeReference);
  }

  Future<String> renderBytesAsBase64({
    required Uint8List bytes,
    required String rangeReference,
  }) async {
    if (bytes.isEmpty ||
        bytes.length > ProjectStorageService.maxFileSizeBytes) {
      throw ArgumentError('Selecione uma planilha XLSX de até 25 MB.');
    }
    final workbook = excel.Excel.decodeBytes(bytes);
    final (sheetName, range) = _parseReference(rangeReference);
    final matchingSheet = workbook.tables.keys.where(
      (name) => name.toLowerCase() == sheetName.toLowerCase(),
    );
    if (matchingSheet.isEmpty) {
      throw StateError('A planilha "$sheetName" não existe neste arquivo.');
    }

    final sheet = workbook.tables[matchingSheet.first]!;
    final rangeParts = range.split(':');
    final start = excel.CellIndex.indexByString(rangeParts.first);
    final end = excel.CellIndex.indexByString(rangeParts.last);
    if (end.rowIndex < start.rowIndex || end.columnIndex < start.columnIndex) {
      throw ArgumentError(
          'Informe o intervalo do canto superior esquerdo ao inferior direito.');
    }
    final rowCount = (end.rowIndex - start.rowIndex).abs() + 1;
    final columnCount = (end.columnIndex - start.columnIndex).abs() + 1;
    if (rowCount > _maxRows ||
        columnCount > _maxColumns ||
        rowCount * columnCount > _maxCells) {
      throw ArgumentError(
        'O intervalo excede o limite de $_maxRows linhas, '
        '$_maxColumns colunas ou $_maxCells células.',
      );
    }

    final selectedRows = sheet.selectRange(start, end: end);
    final values = List<List<String>>.generate(rowCount, (rowIndex) {
      final selectedRow = selectedRows.elementAtOrNull(rowIndex);
      return List<String>.generate(columnCount, (columnIndex) {
        final cell = selectedRow?.elementAtOrNull(columnIndex);
        return _cellValueToText(cell?.value);
      });
    });

    return _renderTable(values);
  }

  (String, String) _parseReference(String reference) {
    var value = reference.trim();
    if (value.startsWith('=')) {
      value = value.substring(1);
    }

    var sheetName = 'Dados';
    if (value.contains('!')) {
      final separator = value.lastIndexOf('!');
      sheetName = value.substring(0, separator).trim();
      if (sheetName.startsWith("'") && sheetName.endsWith("'")) {
        sheetName = sheetName.substring(1, sheetName.length - 1);
      }
      sheetName = sheetName.replaceAll("''", "'");
      value = value.substring(separator + 1);
    }

    final range = value.replaceAll('\$', '').toUpperCase();
    if (!RegExp(r'^[A-Z]{1,3}\d+:[A-Z]{1,3}\d+$').hasMatch(range)) {
      throw ArgumentError('Intervalo do Excel inválido: $reference');
    }
    for (final address in range.split(':')) {
      final cell = excel.CellIndex.indexByString(address);
      if (cell.rowIndex < 0 ||
          cell.rowIndex >= 1048576 ||
          cell.columnIndex < 0 ||
          cell.columnIndex >= 16384) {
        throw ArgumentError(
            'O intervalo está fora dos limites de uma planilha Excel.');
      }
    }
    if (sheetName.isEmpty) {
      sheetName = 'Dados';
    }
    return (sheetName, range);
  }

  String _cellValueToText(excel.CellValue? value) {
    return switch (value) {
      null => '',
      excel.TextCellValue(:final value) => value.text ?? '',
      excel.IntCellValue(:final value) => value.toString(),
      excel.DoubleCellValue(:final value) => value.toString(),
      excel.DateCellValue(:final year, :final month, :final day) =>
        '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
      excel.DateTimeCellValue(
        :final year,
        :final month,
        :final day,
        :final hour,
        :final minute
      ) =>
        '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} '
            '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
      excel.TimeCellValue(:final hour, :final minute, :final second) =>
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}',
      excel.BoolCellValue(:final value) => value.toString(),
      excel.FormulaCellValue(:final formula) => formula,
    };
  }

  Future<String> _renderTable(List<List<String>> rows) async {
    if (rows.isEmpty || rows.first.isEmpty) {
      throw StateError('O intervalo selecionado não contém células.');
    }

    final columnWidths = List<double>.generate(rows.first.length, (column) {
      final maxLength = rows.map((row) => row[column].length).fold<int>(
          0, (current, length) => length > current ? length : current);
      return (maxLength * 7.0 + 24).clamp(76.0, 220.0).toDouble();
    });
    const rowHeight = 34.0;
    final naturalWidth =
        columnWidths.fold<double>(0, (sum, width) => sum + width);
    final naturalHeight = rows.length * rowHeight;
    final scale = [
      1.0,
      _maxImageWidth / naturalWidth,
      _maxImageHeight / naturalHeight,
    ].reduce((left, right) => left < right ? left : right);
    final width =
        (naturalWidth * scale).ceil().clamp(1, _maxImageWidth.toInt()).toInt();
    final height = (naturalHeight * scale)
        .ceil()
        .clamp(1, _maxImageHeight.toInt())
        .toInt();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);

    final borderPaint = Paint()
      ..color = const Color(0xFFB7C0CC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final headerPaint = Paint()..color = const Color(0xFFE8EDF3);

    var x = 0.0;
    for (var column = 0; column < columnWidths.length; column++) {
      final cellWidth = columnWidths[column] * scale;
      for (var row = 0; row < rows.length; row++) {
        final rect = Rect.fromLTWH(
          x,
          row * rowHeight * scale,
          cellWidth,
          rowHeight * scale,
        );
        if (row == 0) {
          canvas.drawRect(rect, headerPaint);
        }
        canvas.drawRect(rect, borderPaint);

        final painter = TextPainter(
          text: TextSpan(
            text: rows[row][column],
            style: TextStyle(
              color: const Color(0xFF17202A),
              fontSize: 12 * scale,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: (cellWidth - 12 * scale).clamp(1.0, cellWidth));
        painter.paint(
          canvas,
          Offset(x + 6 * scale, row * rowHeight * scale + 6 * scale),
        );
      }
      x += cellWidth;
    }

    final image = await recorder.endRecording().toImage(width, height);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (png == null) {
      throw StateError('Não foi possível criar a imagem do intervalo Excel.');
    }
    return base64Encode(png.buffer.asUint8List());
  }
}

extension<T> on Iterable<T> {
  T? elementAtOrNull(int index) {
    if (index < 0) {
      return null;
    }
    final iterator = this.iterator;
    for (var i = 0; iterator.moveNext(); i++) {
      if (i == index) {
        return iterator.current;
      }
    }
    return null;
  }
}
