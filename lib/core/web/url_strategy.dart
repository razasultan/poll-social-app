/// Configures path-based URLs (no `#/`) when running on the web, so links
/// like `/p/:shareSlug` work without a hash fragment. No-op elsewhere.
///
/// `flutter_web_plugins` depends on `dart:ui_web`, which only exists for the
/// web compiler — importing it unconditionally breaks VM targets (including
/// `flutter test`). The conditional export below swaps in a no-op stub there.
library;

export 'url_strategy_stub.dart' if (dart.library.html) 'url_strategy_web.dart';
