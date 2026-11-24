import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Generates a simple landscape A4 completion certificate as PDF bytes.
class CertificateService {
  static Future<Uint8List> build({required String name, required String exam, required double percent}) async {
    final doc = pw.Document();
    final date = DateFormat('d MMMM yyyy').format(DateTime.now());
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColor.fromHex('#0B7A4B'), width: 6)),
        padding: const pw.EdgeInsets.all(32),
        child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
          pw.Text('STUDY BD', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#0B7A4B'))),
          pw.SizedBox(height: 12),
          pw.Text('Certificate of Achievement', style: pw.TextStyle(fontSize: 36, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 24),
          pw.Text('This is proudly presented to', style: const pw.TextStyle(fontSize: 16)),
          pw.SizedBox(height: 8),
          pw.Text(name, style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 16),
          pw.Text('for successfully completing', style: const pw.TextStyle(fontSize: 16)),
          pw.SizedBox(height: 8),
          pw.Text(exam, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
          pw.SizedBox(height: 8),
          pw.Text('with a score of ${percent.toStringAsFixed(1)}%', style: const pw.TextStyle(fontSize: 16)),
          pw.SizedBox(height: 28),
          pw.Text(date, style: const pw.TextStyle(fontSize: 12)),
        ]),
      ),
    ));
    return doc.save();
  }
}
