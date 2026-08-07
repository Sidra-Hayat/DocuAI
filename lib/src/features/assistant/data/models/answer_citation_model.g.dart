// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'answer_citation_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AnswerCitationModelAdapter extends TypeAdapter<AnswerCitationModel> {
  @override
  final typeId = 4;

  @override
  AnswerCitationModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AnswerCitationModel(
      documentId: fields[0] as String,
      documentTitle: fields[1] as String,
      pageIndex: (fields[2] as num).toInt(),
      snippet: fields[3] as String,
      matchedTerms: (fields[4] as List?)?.cast<String>(),
      relevance: (fields[5] as num?)?.toDouble(),
    );
  }

  @override
  void write(BinaryWriter writer, AnswerCitationModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.documentId)
      ..writeByte(1)
      ..write(obj.documentTitle)
      ..writeByte(2)
      ..write(obj.pageIndex)
      ..writeByte(3)
      ..write(obj.snippet)
      ..writeByte(4)
      ..write(obj.matchedTerms)
      ..writeByte(5)
      ..write(obj.relevance);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnswerCitationModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
