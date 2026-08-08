// أداة لتحويل النص العربي إلى صورة قبل وضعه في الـPDF.
//
// المشكلة: مكتبة `pdf` ما بتدعـم shaping العربية — الحروف بتطلعة متقطعة
// واتجاه RTL مش مضبوط باستخدام `pw.Text` العادي.
// الحل: نرسم النص بـ Flutter canvas (اللي بيدعم العربية الـproper) ونحوله
// لـ PNG bytes، وبعدين نحطه كـ `pw.Image` في الـPDF.
//
// ملاحظة: تم إزالة _fontFamily المخصص عشان في بيئة الـRelease بيفشل التحميل
// ويرجع fallback فارغ — font النظام الافتراضي بيدعم Arabic shaping صح.
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';

class RasterizedText {
  final Uint8List bytes;
  /// العرض الفعلي للصورة المولّدة بالنقاط (points) قبل الـpixelRatio
  final double widthPts;
  /// الارتفاع الفعلي للصورة المولّدة بالنقاط (points) قبل الـpixelRatio
  final double heightPts;

  const RasterizedText({
    required this.bytes,
    required this.widthPts,
    required this.heightPts,
  });
}

class ArabicTextRasterizer {
  /// يحوّل نص (عربي أو إنجليزي) إلى PNG bytes مع أبعاد الصورة الفعلية.
  ///
  /// [pixelRatio] يتحكم في جودة الصورة — 2.0 مناسب لطابعات الملصقات (203 DPI).
  /// [maxWidth] أقصى عرض بالنقاط (points) — لو النص أطول بيتكسر على سطر تاني.
  static Future<RasterizedText> render({
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
          // بدون fontFamily — يستخدم font النظام اللي بيدعم العربية صح في Windows
        ),
      ),
      textDirection: direction,
      textAlign: textAlign,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);

    final widthPts = textPainter.width + padding * 2;
    final heightPts = textPainter.height + padding * 2;

    final wPx = (widthPts * pixelRatio).ceil();
    final hPx = (heightPts * pixelRatio).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pixelRatio);

    // خلفية بيضاء
    canvas.drawRect(
      Rect.fromLTWH(0, 0, widthPts, heightPts),
      Paint()..color = Colors.white,
    );

    textPainter.paint(canvas, Offset(padding, padding));

    final picture = recorder.endRecording();
    final image = await picture.toImage(wPx, hPx);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return RasterizedText(
      bytes: byteData!.buffer.asUint8List(),
      widthPts: widthPts,
      heightPts: heightPts,
    );
  }
}
