import 'package:flutter/material.dart';

import '../../../core/network/api_transport.dart';
import '../../../shared/models/record.dart';
import '../../memory/screens/record_detail_screen.dart';
import '../../group/screens/group_detail_management_screen.dart';
import '../../group/services/group_list_store.dart';
import '../models/notification_item_data.dart';
import '../services/notification_api.dart';
import '../widgets/notification_list_item.dart';
import 'notification_settings_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationItemData> _items = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await NotificationApi.load();
      await NotificationApi.refreshUnreadCount();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '알림을 처리하지 못했어요. 다시 시도해 주세요.';
        });
      }
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _open(NotificationItemData item) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await NotificationApi.read(item.id);
      await _load();
      final id = item.referenceId;
      if (id == null) return;
      Widget target;
      if (item.referenceType == 'RECORD') {
        Record? record;
        var offset = 0;
        while (record == null) {
          final page =
              await ApiTransport.get('/feed?limit=100&offset=$offset') as Map;
          final batch = page['items'] as List;
          for (final raw in batch) {
            if ((raw as Map)['id'].toString() == id.toString()) {
              record = Record.fromJson(Map<String, dynamic>.from(raw));
            }
          }
          offset += batch.length;
          if (batch.isEmpty || offset >= (page['total'] as int)) break;
        }
        if (record == null) {
          _message('삭제되었거나 접근할 수 없는 기록이에요.');
          return;
        }
        target = RecordDetailScreen(record: record);
      } else if (item.referenceType == 'GROUP') {
        await GroupListStore.refreshGroups();
        if (!GroupListStore.groups.any((group) => group.id == '$id')) {
          _message('삭제되었거나 접근할 수 없는 모임이에요.');
          return;
        }
        target = GroupDetailManagementScreen(groupId: '$id');
      } else {
        _message('연결된 내용을 열 수 없어요.');
        return;
      }
      if (mounted) {
        await Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => target));
      }
    } catch (_) {
      _message('알림을 처리하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await NotificationApi.readAll();
      await _load();
    } catch (_) {
      _message('읽음 처리하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('알림'),
      actions: [
        IconButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const NotificationSettingsScreen(),
            ),
          ),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: NotificationApi.unreadCount,
                  builder: (_, count, _) => Text('읽지 않은 알림 $count개'),
                ),
                if (_error != null) ...[
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('다시 시도')),
                ] else if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('아직 알림이 없어요.', textAlign: TextAlign.center),
                  )
                else ...[
                  TextButton(
                    onPressed: _busy ? null : _readAll,
                    child: const Text('모두 읽음으로 표시'),
                  ),
                  for (final item in _items)
                    NotificationListItem(item: item, onTap: () => _open(item)),
                ],
              ],
            ),
          ),
  );
}
