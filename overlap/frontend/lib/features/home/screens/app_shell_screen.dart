import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../group/screens/groups_screen.dart';
import '../../map/screens/map_screen.dart';
import '../../memory/screens/feed_screen.dart';
import '../../memory/screens/record_compose_screen.dart';
import '../../user/screens/profile_screen.dart';

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});

  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> {
  int _selectedIndex = 0;

  static const _screens = <Widget>[
    MapScreen(),
    FeedScreen(),
    RecordComposeScreen(),
    GroupsScreen(),
    ProfileScreen(),
  ];

  static const _items = <_NavigationItem>[
    _NavigationItem('지도', Icons.map_outlined, Icons.map),
    _NavigationItem('피드', Icons.view_stream_outlined, Icons.view_stream),
    _NavigationItem('새 기록', Icons.add, Icons.add),
    _NavigationItem('모임', Icons.groups_outlined, Icons.groups),
    _NavigationItem('나', Icons.person_outline, Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _selectedIndex, children: _screens),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 70,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: List.generate(_items.length, (index) {
              final item = _items[index];
              return Expanded(
                child: _BottomNavigationItem(
                  item: item,
                  selected: _selectedIndex == index,
                  isCompose: index == 2,
                  onTap: () => setState(() => _selectedIndex = index),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavigationItem {
  const _NavigationItem(this.label, this.outlinedIcon, this.selectedIcon);

  final String label;
  final IconData outlinedIcon;
  final IconData selectedIcon;
}

class _BottomNavigationItem extends StatelessWidget {
  const _BottomNavigationItem({
    required this.item,
    required this.selected,
    required this.isCompose,
    required this.onTap,
  });

  final _NavigationItem item;
  final bool selected;
  final bool isCompose;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.deepNavy : AppColors.muted;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs, bottom: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isCompose)
                Container(
                  width: 42,
                  height: 42,
                  margin: const EdgeInsets.only(bottom: 1),
                  decoration: const BoxDecoration(
                    color: AppColors.coral,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x33FF7058),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(Icons.add, color: Colors.white),
                )
              else
                Icon(
                  selected ? item.selectedIcon : item.outlinedIcon,
                  color: color,
                  size: 22,
                ),
              SizedBox(height: isCompose ? 0 : 2),
              Text(
                isCompose ? '+' : item.label,
                style: TextStyle(
                  color: isCompose ? AppColors.coral : color,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
