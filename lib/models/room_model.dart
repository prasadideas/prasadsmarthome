class RoomModel {
  final String roomId;
  final String roomName;
  final String icon;
  final List<String> deviceRefs; // stores device document paths

  RoomModel({
    required this.roomId,
    required this.roomName,
    required this.icon,
    required this.deviceRefs,
  });

  factory RoomModel.fromMap(String id, Map<String, dynamic> map) {
    return RoomModel(
      roomId: id,
      roomName: map['roomName'] ?? '',
      icon: map['icon'] ?? 'devices',
      deviceRefs: List<String>.from(map['deviceRefs'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'roomName': roomName,
      'icon': icon,
      'deviceRefs': deviceRefs,
    };
  }
}