import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class StaffDashboardIcon extends StatelessWidget {
  const StaffDashboardIcon(this.name, {super.key, this.color});

  final String name;
  final Color? color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/staff_dashboard/$name.svg',
    excludeFromSemantics: true,
    colorFilter: color == null ? null : ColorFilter.mode(color!, BlendMode.srcIn),
  );
}

Card staffDashboardCard(BuildContext context, Widget child, {double radius = 16}) => Card(
  clipBehavior: Clip.antiAlias,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
  ),
  child: child,
);

enum StaffShortcutTone {
  blue(0xFFD9F0FC, 0xFF162D41),
  violet(0xFFE8E3FC, 0xFF2A2340),
  green(0xFFDEF5E8, 0xFF173A2A),
  gold(0xFFFCEDCF, 0xFF3A2C10),
  sky(0xFFDBF0FA, 0xFF162D41),
  indigo(0xFFE5EDFC, 0xFF22344F),
  paleBlue(0xFFE5EFFB, 0xFF22344F),
  paleGold(0xFFFBEFD8, 0xFF3A2C10),
  paleGreen(0xFFDDF4E7, 0xFF173A2A),
  paleViolet(0xFFECE6FB, 0xFF2A2340);

  const StaffShortcutTone(this.light, this.dark);

  final int light;
  final int dark;

  Color background(ColorScheme scheme) => Color(scheme.brightness == Brightness.dark ? dark : light);
}
