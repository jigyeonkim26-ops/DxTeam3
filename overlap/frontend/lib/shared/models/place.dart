/// 장소 기록과 지도 표시에서 공통으로 사용하는 장소 정보입니다.
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.address,
    this.recordCount = 0,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String? address;
  final int recordCount;
}
