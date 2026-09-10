import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayanything/design.dart';
import 'dart:math' as math;

void main() {
  testWidgets('page titles remain readable on the dark application background', (tester) async {
    const background = Color(0xFF141414);
    await tester.pumpWidget(MaterialApp(theme: appTheme(true), home: Scaffold(backgroundColor: background, appBar: AppBar(title: const Text('对话标题')))));
    final title = tester.widgetList<RichText>(find.byType(RichText)).firstWhere((w) => w.text.toPlainText() == '对话标题');
    final color = title.text.style?.color ?? Colors.black;
    final foregroundLuminance = color.computeLuminance();
    final backgroundLuminance = background.computeLuminance();
    final contrast = (math.max(foregroundLuminance, backgroundLuminance) + .05) / (math.min(foregroundLuminance, backgroundLuminance) + .05);
    expect(contrast, greaterThanOrEqualTo(4.5));
  });
}
