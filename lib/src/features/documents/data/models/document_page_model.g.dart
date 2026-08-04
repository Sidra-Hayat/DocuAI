// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'document_page_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DocumentPageModelAdapter extends TypeAdapter<DocumentPageModel> {
  @override
  final typeId = 1;

  @override
  DocumentPageModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DocumentPageModel(
      id: fields[0] as String,
      imagePath: fields[1] as String,
      index: (fields[2] as num).toInt(),
      text: fields[3] as String,
      ocrStatus: fields[4] as String,
    );
  }

  @override
  void write(BinaryWriter writer, DocumentPageModel obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.imagePath)
      ..writeByte(2)
      ..write(obj.index)
      ..writeByte(3)
      ..write(obj.text)
      ..writeByte(4)
      ..write(obj.ocrStatus);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentPageModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
