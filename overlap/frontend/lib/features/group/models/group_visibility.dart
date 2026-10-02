enum GroupVisibility {
  invitedMembersOnly,
  linkRequestAllowed;

  String get label => switch (this) {
    GroupVisibility.invitedMembersOnly => '초대받은 멤버만',
    GroupVisibility.linkRequestAllowed => '링크를 가진 사람은 참여 요청 가능',
  };
}
