import 'package:flutter/widgets.dart';

/// Shared width breakpoints. Every screen uses these same numbers.
class Breakpoints {
  Breakpoints._();

  /// Below this width the layout switches to the mobile arrangement.
  static const double mobile = 600;

  /// Between [mobile] and this width the layout is a narrow desktop window.
  static const double tablet = 1000;
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  bool get isMobileWidth => screenWidth < Breakpoints.mobile;

  bool get isTabletWidth =>
      screenWidth >= Breakpoints.mobile && screenWidth < Breakpoints.tablet;

  bool get isDesktopWidth => screenWidth >= Breakpoints.tablet;
}

/// Dialog width that never exceeds 90% of the screen.
///
/// On a desktop window `max(1280) * 0.9 = 1152`, so any dialog narrower than
/// that keeps its requested width and the desktop layout is untouched.
double dialogWidth(BuildContext context, double desired) {
  final maxWidth = MediaQuery.sizeOf(context).width * 0.9;
  return desired < maxWidth ? desired : maxWidth;
}

/// Upper bound for dialog content, so a short screen (or an open keyboard)
/// cannot push the buttons off-screen.
double dialogMaxHeight(BuildContext context) {
  return MediaQuery.sizeOf(context).height * 0.8;
}
