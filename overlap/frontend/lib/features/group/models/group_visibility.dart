enum GroupVisibility {
  invitedMembersOnly,
  linkRequestAllowed;

  String get label => switch (this) {
    GroupVisibility.invitedMembersOnly => '초대받은 멤버만',
    GroupVisibility.linkRequestAllowed => '링크를 가진 사람은 바로 참여 가능',
  };

  String get apiValue => switch (this) {
    GroupVisibility.invitedMembersOnly => 'INVITED_ONLY',
    GroupVisibility.linkRequestAllowed => 'LINK_REQUEST_ALLOWED',
  };
}
