class GroupInvitePreview {
  const GroupInvitePreview({
    required this.groupName,
    required this.ownerName,
    required this.memberCount,
    required this.placeCount,
    required this.inviteCode,
  });

  final String groupName;
  final String ownerName;
  final int memberCount;
  final int placeCount;
  final String inviteCode;
}
