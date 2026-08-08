// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChatMessage {

 String get id; ChatRole get role; String get text; DateTime get createdAt;/// Which document this turn belongs to, or null for the library-wide
/// conversation.
///
/// Scope lives on the message rather than in a box per document. A box per
/// document would mean opening one per conversation and remembering to
/// delete it with the document; a nullable field makes "every
/// conversation" a filter instead of a fan-out.
 String? get documentId;/// Which conversation this turn belongs to.
///
/// Null on every message written before conversations existed. Those are
/// not orphans: [conversation] folds them into one conversation per scope,
/// which is exactly what they were.
 String? get conversationId;/// Populated on assistant turns only, and kept on the message rather than
/// recomputed, so scrolling back through the transcript shows the sources
/// that answer was actually built from.
 List<AnswerCitation> get citations;/// Set when the turn failed. The message stays in the transcript carrying
/// the reason, which reads better than a snackbar that disappears and
/// leaves an unanswered question on screen.
 String? get errorMessage;
/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatMessageCopyWith<ChatMessage> get copyWith => _$ChatMessageCopyWithImpl<ChatMessage>(this as ChatMessage, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatMessage&&(identical(other.id, id) || other.id == id)&&(identical(other.role, role) || other.role == role)&&(identical(other.text, text) || other.text == text)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.documentId, documentId) || other.documentId == documentId)&&(identical(other.conversationId, conversationId) || other.conversationId == conversationId)&&const DeepCollectionEquality().equals(other.citations, citations)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode => Object.hash(runtimeType,id,role,text,createdAt,documentId,conversationId,const DeepCollectionEquality().hash(citations),errorMessage);

@override
String toString() {
  return 'ChatMessage(id: $id, role: $role, text: $text, createdAt: $createdAt, documentId: $documentId, conversationId: $conversationId, citations: $citations, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class $ChatMessageCopyWith<$Res>  {
  factory $ChatMessageCopyWith(ChatMessage value, $Res Function(ChatMessage) _then) = _$ChatMessageCopyWithImpl;
@useResult
$Res call({
 String id, ChatRole role, String text, DateTime createdAt, String? documentId, String? conversationId, List<AnswerCitation> citations, String? errorMessage
});




}
/// @nodoc
class _$ChatMessageCopyWithImpl<$Res>
    implements $ChatMessageCopyWith<$Res> {
  _$ChatMessageCopyWithImpl(this._self, this._then);

  final ChatMessage _self;
  final $Res Function(ChatMessage) _then;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? role = null,Object? text = null,Object? createdAt = null,Object? documentId = freezed,Object? conversationId = freezed,Object? citations = null,Object? errorMessage = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as ChatRole,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,documentId: freezed == documentId ? _self.documentId : documentId // ignore: cast_nullable_to_non_nullable
as String?,conversationId: freezed == conversationId ? _self.conversationId : conversationId // ignore: cast_nullable_to_non_nullable
as String?,citations: null == citations ? _self.citations : citations // ignore: cast_nullable_to_non_nullable
as List<AnswerCitation>,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatMessage].
extension ChatMessagePatterns on ChatMessage {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatMessage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatMessage value)  $default,){
final _that = this;
switch (_that) {
case _ChatMessage():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatMessage value)?  $default,){
final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  ChatRole role,  String text,  DateTime createdAt,  String? documentId,  String? conversationId,  List<AnswerCitation> citations,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
return $default(_that.id,_that.role,_that.text,_that.createdAt,_that.documentId,_that.conversationId,_that.citations,_that.errorMessage);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  ChatRole role,  String text,  DateTime createdAt,  String? documentId,  String? conversationId,  List<AnswerCitation> citations,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _ChatMessage():
return $default(_that.id,_that.role,_that.text,_that.createdAt,_that.documentId,_that.conversationId,_that.citations,_that.errorMessage);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  ChatRole role,  String text,  DateTime createdAt,  String? documentId,  String? conversationId,  List<AnswerCitation> citations,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
return $default(_that.id,_that.role,_that.text,_that.createdAt,_that.documentId,_that.conversationId,_that.citations,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc


class _ChatMessage extends ChatMessage {
  const _ChatMessage({required this.id, required this.role, required this.text, required this.createdAt, this.documentId, this.conversationId, final  List<AnswerCitation> citations = const <AnswerCitation>[], this.errorMessage}): _citations = citations,super._();
  

@override final  String id;
@override final  ChatRole role;
@override final  String text;
@override final  DateTime createdAt;
/// Which document this turn belongs to, or null for the library-wide
/// conversation.
///
/// Scope lives on the message rather than in a box per document. A box per
/// document would mean opening one per conversation and remembering to
/// delete it with the document; a nullable field makes "every
/// conversation" a filter instead of a fan-out.
@override final  String? documentId;
/// Which conversation this turn belongs to.
///
/// Null on every message written before conversations existed. Those are
/// not orphans: [conversation] folds them into one conversation per scope,
/// which is exactly what they were.
@override final  String? conversationId;
/// Populated on assistant turns only, and kept on the message rather than
/// recomputed, so scrolling back through the transcript shows the sources
/// that answer was actually built from.
 final  List<AnswerCitation> _citations;
/// Populated on assistant turns only, and kept on the message rather than
/// recomputed, so scrolling back through the transcript shows the sources
/// that answer was actually built from.
@override@JsonKey() List<AnswerCitation> get citations {
  if (_citations is EqualUnmodifiableListView) return _citations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_citations);
}

/// Set when the turn failed. The message stays in the transcript carrying
/// the reason, which reads better than a snackbar that disappears and
/// leaves an unanswered question on screen.
@override final  String? errorMessage;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatMessageCopyWith<_ChatMessage> get copyWith => __$ChatMessageCopyWithImpl<_ChatMessage>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatMessage&&(identical(other.id, id) || other.id == id)&&(identical(other.role, role) || other.role == role)&&(identical(other.text, text) || other.text == text)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.documentId, documentId) || other.documentId == documentId)&&(identical(other.conversationId, conversationId) || other.conversationId == conversationId)&&const DeepCollectionEquality().equals(other._citations, _citations)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode => Object.hash(runtimeType,id,role,text,createdAt,documentId,conversationId,const DeepCollectionEquality().hash(_citations),errorMessage);

@override
String toString() {
  return 'ChatMessage(id: $id, role: $role, text: $text, createdAt: $createdAt, documentId: $documentId, conversationId: $conversationId, citations: $citations, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$ChatMessageCopyWith<$Res> implements $ChatMessageCopyWith<$Res> {
  factory _$ChatMessageCopyWith(_ChatMessage value, $Res Function(_ChatMessage) _then) = __$ChatMessageCopyWithImpl;
@override @useResult
$Res call({
 String id, ChatRole role, String text, DateTime createdAt, String? documentId, String? conversationId, List<AnswerCitation> citations, String? errorMessage
});




}
/// @nodoc
class __$ChatMessageCopyWithImpl<$Res>
    implements _$ChatMessageCopyWith<$Res> {
  __$ChatMessageCopyWithImpl(this._self, this._then);

  final _ChatMessage _self;
  final $Res Function(_ChatMessage) _then;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? role = null,Object? text = null,Object? createdAt = null,Object? documentId = freezed,Object? conversationId = freezed,Object? citations = null,Object? errorMessage = freezed,}) {
  return _then(_ChatMessage(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as ChatRole,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,documentId: freezed == documentId ? _self.documentId : documentId // ignore: cast_nullable_to_non_nullable
as String?,conversationId: freezed == conversationId ? _self.conversationId : conversationId // ignore: cast_nullable_to_non_nullable
as String?,citations: null == citations ? _self._citations : citations // ignore: cast_nullable_to_non_nullable
as List<AnswerCitation>,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
