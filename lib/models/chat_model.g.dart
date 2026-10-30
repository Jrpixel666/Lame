// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ChatModelAdapter extends TypeAdapter<ChatModel> {
  @override
  final int typeId = 0;

  @override
  ChatModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatModel(
      id: fields[0] as String,
      title: fields[1] as String? ?? 'New Chat',
      modelId: fields[2] as String? ?? '',
      systemPrompt: fields[3] as String? ?? '',
      messages: (fields[4] as List?)?.cast<MessageModel>() ?? [],
      createdAt: fields[5] as DateTime?,
      updatedAt: fields[6] as DateTime?,
      mode: fields[7] as ChatMode? ?? ChatMode.chat,
    );
  }

  @override
  void write(BinaryWriter writer, ChatModel obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.modelId)
      ..writeByte(3)
      ..write(obj.systemPrompt)
      ..writeByte(4)
      ..write(obj.messages)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.updatedAt)
      ..writeByte(7)
      ..write(obj.mode);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ChatModeAdapter extends TypeAdapter<ChatMode> {
  @override
  final int typeId = 3;

  @override
  ChatMode read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ChatMode.chat;
      case 1:
        return ChatMode.development;
      default:
        return ChatMode.chat;
    }
  }

  @override
  void write(BinaryWriter writer, ChatMode obj) {
    switch (obj) {
      case ChatMode.chat:
        writer.writeByte(0);
        break;
      case ChatMode.development:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatModeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
