import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/core/network/api_config.dart';
import 'package:overlap_app/core/network/api_transport.dart';
import 'package:overlap_app/features/comment/models/comment_item.dart';
import 'package:overlap_app/features/comment/widgets/comment_thread.dart';
import 'package:overlap_app/features/memory/widgets/record_author_avatar.dart';
import 'package:overlap_app/shared/models/user.dart';

void main() {
  tearDown(ApiTransport.clearAccessToken);

  testWidgets('comment and reply use authenticated profile photo URLs', (
    tester,
  ) async {
    ApiTransport.setAccessToken('comment-token');
    final parent = CommentItem(
      id: '3',
      author: const User(
        id: '1',
        name: 'Parent',
        profileImagePath: '/records/1/comments/3/author-photo?v=one',
      ),
      createdAt: DateTime(2026),
      content: 'Parent comment',
      replies: [
        CommentItem(
          id: '4',
          author: const User(
            id: '2',
            name: 'Reply',
            profileImagePath: '/records/1/comments/4/author-photo?v=two',
          ),
          createdAt: DateTime(2026),
          content: 'Reply comment',
          parentCommentId: '3',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentThread(comment: parent, onReply: () {}),
        ),
      ),
    );

    final avatars = find.byType(RecordAuthorAvatar);
    expect(avatars, findsNWidgets(2));
    final images = tester
        .widgetList<Image>(
          find.descendant(of: avatars, matching: find.byType(Image)),
        )
        .toList();
    expect(images, hasLength(2));
    for (final (index, image) in images.indexed) {
      final provider = image.image as NetworkImage;
      expect(
        provider.url,
        '${ApiConfig.baseUrl}/records/1/comments/${index + 3}/author-photo?v=${index == 0 ? 'one' : 'two'}',
      );
      expect(provider.headers?['Authorization'], 'Bearer comment-token');
    }
  });

  testWidgets('missing photos keep the initial avatars', (tester) async {
    final parent = CommentItem(
      id: '3',
      author: const User(id: '1', name: 'Parent'),
      createdAt: DateTime(2026),
      content: 'Parent comment',
      replies: [
        CommentItem(
          id: '4',
          author: const User(id: '2', name: 'Reply'),
          createdAt: DateTime(2026),
          content: 'Reply comment',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentThread(comment: parent, onReply: () {}),
        ),
      ),
    );

    final avatars = find.byType(RecordAuthorAvatar);
    expect(avatars, findsNWidgets(2));
    expect(
      find.descendant(of: avatars, matching: find.byType(Image)),
      findsNothing,
    );
    expect(
      find.descendant(of: avatars, matching: find.text('P')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: avatars, matching: find.text('R')),
      findsOneWidget,
    );
  });
}
