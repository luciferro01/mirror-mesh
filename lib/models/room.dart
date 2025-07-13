import 'dart:typed_data';

import 'package:json_annotation/json_annotation.dart';

part 'room.g.dart';

@JsonSerializable()
class Room {
  final String id;
  final String code;
  final String hostId;
  final DateTime createdAt;
  final List<String> connectedViewers;
  final QualitySettings qualitySettings;
  @JsonKey(includeFromJson: false, includeToJson: false)
  final ScreenSource? activeScreenSource;
  final bool isActive;
  final String? hostIP;
  final int? serverPort;

  Room({
    required this.id,
    required this.code,
    required this.hostId,
    required this.createdAt,
    this.connectedViewers = const [],
    required this.qualitySettings,
    this.activeScreenSource,
    this.isActive = false,
    this.hostIP,
    this.serverPort,
  });

  factory Room.fromJson(Map<String, dynamic> json) => _$RoomFromJson(json);
  Map<String, dynamic> toJson() => _$RoomToJson(this);

  Room copyWith({
    String? id,
    String? code,
    String? hostId,
    DateTime? createdAt,
    List<String>? connectedViewers,
    QualitySettings? qualitySettings,
    ScreenSource? activeScreenSource,
    bool? isActive,
    String? hostIP,
    int? serverPort,
  }) {
    return Room(
      id: id ?? this.id,
      code: code ?? this.code,
      hostId: hostId ?? this.hostId,
      createdAt: createdAt ?? this.createdAt,
      connectedViewers: connectedViewers ?? this.connectedViewers,
      qualitySettings: qualitySettings ?? this.qualitySettings,
      activeScreenSource: activeScreenSource ?? this.activeScreenSource,
      isActive: isActive ?? this.isActive,
      hostIP: hostIP ?? this.hostIP,
      serverPort: serverPort ?? this.serverPort,
    );
  }

  String get connectionUrl => hostIP != null && serverPort != null
      ? 'http://$hostIP:$serverPort/room/$code'
      : '';
}

@JsonSerializable()
class QualitySettings {
  final int width;
  final int height;
  final int frameRate;
  final int bitrate;
  final VideoQuality quality;

  QualitySettings({
    required this.width,
    required this.height,
    required this.frameRate,
    required this.bitrate,
    required this.quality,
  });

  factory QualitySettings.fromJson(Map<String, dynamic> json) =>
      _$QualitySettingsFromJson(json);
  Map<String, dynamic> toJson() => _$QualitySettingsToJson(this);

  static QualitySettings get low => QualitySettings(
    width: 1280,
    height: 720,
    frameRate: 24,
    bitrate: 800000,
    quality: VideoQuality.low,
  );

  static QualitySettings get medium => QualitySettings(
    width: 1920,
    height: 1080,
    frameRate: 30,
    bitrate: 2000000,
    quality: VideoQuality.medium,
  );

  static QualitySettings get high => QualitySettings(
    width: 1920,
    height: 1080,
    frameRate: 60,
    bitrate: 4000000,
    quality: VideoQuality.high,
  );

  // Add ultra-high quality option for 60fps
  static QualitySettings get ultra => QualitySettings(
    width: 2560,
    height: 1440,
    frameRate: 60,
    bitrate: 6000000,
    quality: VideoQuality.high,
  );

  QualitySettings copyWith({
    int? width,
    int? height,
    int? frameRate,
    int? bitrate,
    VideoQuality? quality,
  }) {
    return QualitySettings(
      width: width ?? this.width,
      height: height ?? this.height,
      frameRate: frameRate ?? this.frameRate,
      bitrate: bitrate ?? this.bitrate,
      quality: quality ?? this.quality,
    );
  }
}

class ScreenSource {
  final String id;
  final String name;
  final ScreenSourceType type;
  final Uint8List? thumbnail;
  final bool isSelected;

  ScreenSource({
    required this.id,
    required this.name,
    required this.type,
    this.thumbnail,
    this.isSelected = false,
  });

  ScreenSource copyWith({
    String? id,
    String? name,
    ScreenSourceType? type,
    Uint8List? thumbnail,
    bool? isSelected,
  }) {
    return ScreenSource(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      thumbnail: thumbnail ?? this.thumbnail,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

enum VideoQuality { low, medium, high }

enum ScreenSourceType { screen, window, application }
