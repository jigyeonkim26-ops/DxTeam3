class PlacePublic {
  const PlacePublic({
    required this.id,
    required this.groupId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final int id;
  final int groupId;
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  factory PlacePublic.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final groupId = json['group_id'];
    final name = json['name'];
    final address = json['address'];
    final latitude = json['latitude'];
    final longitude = json['longitude'];

    if (id is! int ||
        groupId is! int ||
        name is! String ||
        address is! String ||
        latitude is! num ||
        longitude is! num) {
      throw const FormatException('Invalid place response.');
    }

    return PlacePublic(
      id: id,
      groupId: groupId,
      name: name,
      address: address,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
    );
  }
}
