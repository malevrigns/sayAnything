import 'package:flutter/material.dart';

/// Visibility for cached tabs. Hidden or covered pages must not poll or locate.
class PageActivity extends InheritedWidget {
  final bool active;
  const PageActivity({super.key, required this.active, required super.child});

  static bool isActiveOf(BuildContext context) =>
      (context.dependOnInheritedWidgetOfExactType<PageActivity>()?.active ??
          true) &&
      (ModalRoute.isCurrentOf(context) ?? true);

  @override
  bool updateShouldNotify(PageActivity oldWidget) => active != oldWidget.active;
}
