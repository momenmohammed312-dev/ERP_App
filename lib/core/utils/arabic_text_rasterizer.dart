// أداة لتحويل النص العربي إلى صورة قبل وضعه في الـPDF.
//
// المشكلة: مكتبة `pdf` ما بتدعـمshaping العربية — الحروف بتطلعة متقطعة
// واتجاه RTL مش مضبوط باستخدام `pw.Text` العادي.
// الحل: نرسم النص بـ Flutter canvas (اللي بيدعم العربية الـproper) ونحوله
// لـ PNG bytes، وبعدين نحطه كـ `pw.Image` في الـPDF.
//
// الطريقة دي مستوحاة من thermal_unicode_print / unified_esc_pos_printer /
// printer_label اللي بيعملوا نفس الحاجة للطباعة الحرارية.
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';

class ArabicTextRasterizer {
  static const _fontFamily = 'NotoSansArabic';

  /// يحوّل نص (عربي أو إنجليزي) إلى PNG bytes يقدر يدخل في PDF.
  ///
  /// [pixelRatio] يتحكم في جودة الصورة — 2.0 مناسب لطابعات الملصقات (203 DPI).
  /// [maxWidth] أقصى عرض بالنقاط (points) — لو النص أطول بيتكسر على سطر تاني.
  static Future<Uint8List> render({
    required String text,
    double fontSize = 12,
    FontWeight fontWeight = FontWeight.normal,
    TextAlign textAlign = TextAlign.center,
    TextDirection direction = TextDirection.rtl,
    double maxWidth = 200,
    double pixelRatio = 2.0,
    double padding = 2,
  }) async {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: Colors.black,
          fontFamily: _fontFamily,
        ),
      ),
      textDirection: direction,
      textAlign: textAlign,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);

    final w = (textPainter.width + padding * 2) * pixelRatio;
    final h = (textPainter.height + padding * 2) * pixelRatio;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.scale(pixelRatio);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, w / pixelRatio, h / pixelRatio),
      Paint()..color = Colors.white,
    );

    textPainter.paint(canvas, Offset(padding, padding));

    final picture = recorder.endRecording();
    final image = await picture.toImage(w.ceil(), h.ceil());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
