import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// Legacy semantic names remain for the existing screens; every value is neutral.
const forest = Color(0xFF262626);
const cream = Color(0xFFF5F5F5);
const sage = Color(0xFF292929);
const peach = Color(0xFFBBBBBB);
const ink = Colors.white;
const muted = Color(0xFF999999);
Color gray(double lightness, [double opacity = 1]) =>
    HSLColor.fromAHSL(opacity, 0, 0, lightness / 100).toColor();

ThemeData appTheme(bool dark) {
  const scheme = ColorScheme.dark(
    primary: Colors.white,
    onPrimary: Color(0xFF141414),
    primaryContainer: Color(0xFF303030),
    onPrimaryContainer: Colors.white,
    secondary: Color(0xFFD6D6D6),
    onSecondary: Color(0xFF111111),
    secondaryContainer: Color(0xFF252525),
    onSecondaryContainer: Colors.white,
    tertiary: Color(0xFFBBBBBB),
    onTertiary: Color(0xFF111111),
    tertiaryContainer: Color(0xFF252525),
    onTertiaryContainer: Colors.white,
    surface: Color(0xFF141414),
    onSurface: Colors.white,
    error: Color(0xFFDADADA),
    onError: Color(0xFF111111),
    errorContainer: Color(0xFF333333),
    onErrorContainer: Colors.white,
    outline: Color(0xFF666666),
    outlineVariant: Color(0xFF333333),
  );
  final text = ThemeData.dark().textTheme.apply(
    fontFamily: 'Poppins',
    fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'NotoSansSC'],
    bodyColor: Colors.white,
    displayColor: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: 'Poppins',
    fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'NotoSansSC'],
    textTheme: text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w500,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w500,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, height: 1.7),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 14, height: 1.65),
      labelLarge: text.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
    iconTheme: const IconThemeData(color: cream, size: 21),
    disabledColor: Colors.white24,
    dividerTheme: const DividerThemeData(color: Colors.white10, thickness: .5),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      iconTheme: IconThemeData(color: Colors.white70, size: 21),
      actionsIconTheme: IconThemeData(color: Colors.white70, size: 21),
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 20,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontFamily: 'Poppins',
        fontFamilyFallback: ['NotoSansSC'],
        fontSize: 25,
        fontWeight: FontWeight.w500,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: .035),
      hintStyle: const TextStyle(
        color: Colors.white38,
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Colors.white24, width: .7),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: .91),
        foregroundColor: const Color(0xFF151515),
        disabledBackgroundColor: Colors.white10,
        disabledForegroundColor: Colors.white30,
        minimumSize: const Size(44, 50),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        textStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white70,
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: Colors.white70,
        disabledForegroundColor: Colors.white24,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.all(11),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        minimumSize: const Size(44, 46),
        side: const BorderSide(color: Colors.white12, width: .5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white.withValues(alpha: .035),
      selectedColor: Colors.white.withValues(alpha: .13),
      labelStyle: const TextStyle(fontSize: 12, color: Colors.white60),
      side: BorderSide.none,
      shape: const StadiumBorder(),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Colors.white
            : const Color(0xFF777777),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? const Color(0xFF777777)
            : const Color(0xFF303030),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF181818),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF202020),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontFamily: 'Poppins',
        fontFamilyFallback: ['NotoSansSC'],
        fontWeight: FontWeight.w500,
        fontSize: 21,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xFF222222),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xEE303030),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontFamily: 'Poppins',
        fontSize: 13,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Colors.white60,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Colors.white,
      selectionColor: Colors.white24,
      selectionHandleColor: Colors.white70,
    ),
  );
}

class Glass extends StatelessWidget {
  final Widget child;
  final bool strong;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color? tint;
  const Glass({
    super.key,
    required this.child,
    this.strong = false,
    this.radius = 24,
    this.padding,
    this.tint,
  });
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: strong ? 50 : 4,
        sigmaY: strong ? 50 : 4,
      ),
      child: CustomPaint(
        foregroundPainter: _GlassEdge(radius, strong),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint ?? Colors.white.withValues(alpha: strong ? .055 : .025),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .05),
                blurRadius: strong ? 4 : 0,
                offset: const Offset(2, 2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    ),
  );
}

class GlassChoiceBar<T> extends StatelessWidget {
  final List<({T value, String label})> options;
  final T value;
  final ValueChanged<T> onChanged;
  const GlassChoiceBar({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Glass(
    radius: 32,
    padding: const EdgeInsets.all(6),
    child: Row(
      children: [
        for (final option in options)
          Expanded(
            child: Semantics(
              selected: value == option.value,
              child: TextButton(
                onPressed: () => onChanged(option.value),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  shape: const StadiumBorder(),
                  backgroundColor: value == option.value
                      ? Colors.white10
                      : Colors.transparent,
                  foregroundColor: value == option.value
                      ? Colors.white
                      : Colors.white38,
                ),
                child: Text(option.label),
              ),
            ),
          ),
      ],
    ),
  );
}

class _GlassEdge extends CustomPainter {
  final double radius;
  final bool strong;
  _GlassEdge(this.radius, this.strong);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(.65);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: strong ? .42 : .27),
          Colors.white.withValues(alpha: .10),
          Colors.transparent,
          Colors.transparent,
          Colors.white.withValues(alpha: .08),
          Colors.white.withValues(alpha: strong ? .3 : .2),
        ],
        stops: const [0, .2, .4, .6, .8, 1],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GlassEdge old) =>
      old.radius != radius || old.strong != strong;
}

class Avatar extends StatelessWidget {
  final int index;
  final double size;
  const Avatar(this.index, {super.key, this.size = 42});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .055),
      shape: BoxShape.circle,
    ),
    child: Icon(LucideIcons.userRound, color: Colors.white54, size: size * .45),
  );
}

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 32});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Icon(
      LucideIcons.messagesSquare,
      color: Colors.white.withValues(alpha: .88),
      size: size * .82,
    ),
  );
}

class Garden extends StatelessWidget {
  final double height;
  const Garden({super.key, this.height = 100});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: const Center(child: BrandMark(size: 52)),
  );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -.4,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 7),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white54,
                    height: 1.7,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  final String title, detail;
  final IconData icon;
  final Widget? action;
  const EmptyState(
    this.title,
    this.detail, {
    super.key,
    this.icon = LucideIcons.messageCircle,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white38, size: 38),
        const SizedBox(height: 21),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w500,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white54,
            height: 1.9,
            fontSize: 13,
          ),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

Widget backButton(BuildContext context) => IconButton(
  tooltip: '返回',
  onPressed: () => Navigator.maybePop(context),
  icon: const Icon(LucideIcons.chevronLeft),
);
void toast(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString()),
        duration: const Duration(seconds: 3),
      ),
    );
String relativeTime(dynamic raw) {
  final time = DateTime.tryParse(raw?.toString() ?? '');
  if (time == null) return '';
  final d = DateTime.now().difference(time);
  if (d.inMinutes < 1) return '刚刚';
  if (d.inHours < 1) return '${d.inMinutes} 分钟前';
  if (d.inDays < 1) return '${d.inHours} 小时前';
  if (d.inDays < 7) return '${d.inDays} 天前';
  return '${time.month}月${time.day}日';
}
