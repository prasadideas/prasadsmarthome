import 'package:cloud_firestore/cloud_firestore.dart';

class HomeModel {
  final String homeId;
  final String homeName;
  final String address;

  HomeModel({
    required this.homeId,
    required this.homeName,
    required this.address,
  });

  factory HomeModel.fromMap(String id, Map<String, dynamic> map) {
    return HomeModel(
      homeId: id,
      homeName: map['homeName'] ?? '',
      address: map['address'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'homeName': homeName,
      'address': address,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}