// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Room _$RoomFromJson(Map<String, dynamic> json) => Room(
  id: json['id'] as String,
  code: json['code'] as String,
  hostId: json['hostId'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  connectedViewers:
      (json['connectedViewers'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  qualitySettings: QualitySettings.fromJson(
    json['qualitySettings'] as Map<String, dynamic>,
  ),
  isActive: json['isActive'] as bool? ?? false,
  hostIP: json['hostIP'] as String?,
  serverPort: (json['serverPort'] as num?)?.toInt(),
);

Map<String, dynamic> _$RoomToJson(Room instance) => <String, dynamic>{
  'id': instance.id,
  'code': instance.code,
  'hostId': instance.hostId,
  'createdAt': instance.createdAt.toIso8601String(),
  'connectedViewers': instance.connectedViewers,
  'qualitySettings': instance.qualitySettings,
  'isActive': instance.isActive,
  'hostIP': instance.hostIP,
  'serverPort': instance.serverPort,
};

QualitySettings _$QualitySettingsFromJson(Map<String, dynamic> json) =>
    QualitySettings(
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      frameRate: (json['frameRate'] as num).toInt(),
      bitrate: (json['bitrate'] as num).toInt(),
      quality: $enumDecode(_$VideoQualityEnumMap, json['quality']),
    );

Map<String, dynamic> _$QualitySettingsToJson(QualitySettings instance) =>
    <String, dynamic>{
      'width': instance.width,
      'height': instance.height,
      'frameRate': instance.frameRate,
      'bitrate': instance.bitrate,
      'quality': _$VideoQualityEnumMap[instance.quality]!,
    };

const _$VideoQualityEnumMap = {
  VideoQuality.low: 'low',
  VideoQuality.medium: 'medium',
  VideoQuality.high: 'high',
};
