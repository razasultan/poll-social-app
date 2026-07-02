import 'package:flutter/material.dart';

/// App-wide route observer. Registered in [MyApp] so that any widget mixing
/// in [RouteAware] can subscribe to route lifecycle events.
final RouteObserver<ModalRoute<dynamic>> appRouteObserver =
    RouteObserver<ModalRoute<dynamic>>();
