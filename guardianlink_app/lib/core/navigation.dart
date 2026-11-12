import 'package:flutter/material.dart';

/// Global keys so services (e.g. push notifications) can show dialogs,
/// snackbars and open screens without a BuildContext.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
