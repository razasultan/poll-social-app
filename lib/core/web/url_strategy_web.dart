import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Switches Flutter web from hash-based (`/#/p/abc`) to path-based
/// (`/p/abc`) URLs so shared poll links resolve cleanly.
void configurePathUrlStrategy() {
  usePathUrlStrategy();
}
