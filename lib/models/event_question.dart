import 'toml_codec.dart';

enum EventQuestionType {
  checkbox,
  text;

  String get tomlValue => switch (this) {
    EventQuestionType.checkbox => 'checkbox',
    EventQuestionType.text => 'text',
  };

  static EventQuestionType fromToml(String value) {
    return switch (value) {
      'checkbox' => EventQuestionType.checkbox,
      'text' => EventQuestionType.text,
      _ => throw FormatException('Unknown event question type: $value'),
    };
  }
}

class EventQuestion {
  final String id;
  final String label;
  final EventQuestionType type;

  const EventQuestion({
      required this.id,
      required this.label,
      required this.type,
  });

  EventQuestion copyWith({
      String? id,
      String? label,
      EventQuestionType? type,
  }) {
    return EventQuestion(
      id: id ?? this.id,
      label: label ?? this.label,
      type: type ?? this.type,
    );
  }

  Map<String, dynamic> toTomlMap() {
    return {
      'id': id,
      'label': label,
      'type': type.tomlValue,
    };
  }

  factory EventQuestion.fromTomlMap(Map<String, dynamic> map) {
    return EventQuestion(
      id: map['id'] as String,
      label: map['label'] as String,
      type: EventQuestionType.fromToml(map['type'] as String),
    );
  }
}
