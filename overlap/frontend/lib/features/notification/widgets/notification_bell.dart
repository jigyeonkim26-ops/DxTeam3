import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../services/notification_api.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key, this.onPressed});
  final VoidCallback? onPressed;
  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  Timer? _timer;
  bool _refreshing = false;
  @override
  void initState() {
    super.initState();
    ApiClient.sessionRevision.addListener(_refresh);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await NotificationApi.refreshUnreadCount();
    } catch (_) {
      /* Retry on the next refresh. */
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    ApiClient.sessionRevision.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: NotificationApi.unreadCount,
    builder: (_, count, _) => IconButton(
      onPressed: () {
        widget.onPressed?.call();
        _refresh();
      },
      tooltip: '알림, 읽지 않은 알림 $count개',
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.notifications_none),
      ),
    ),
  );
}
