// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'document_page.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DocumentPage {

 String get id;/// Relative path to the page JPEG, e.g. `documents/<docId>/page_001.jpg`.
 String get imagePath;/// Zero-based position within the parent document.
 int get index;/// Text recognised on this page. Empty until OCR runs.
 String get text; OcrStatus get ocrStatus;
/// Create a copy of DocumentPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DocumentPageCopyWith<DocumentPage> get copyWith => _$DocumentPageCopyWithImpl<DocumentPage>(this as DocumentPage, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DocumentPage&&(identical(other.id, id) || other.id == id)&&(identical(other.imagePath, imagePath) || other.imagePath == imagePath)&&(identical(other.index, index) || other.index == index)&&(identical(other.text, text) || other.text == text)&&(identical(other.ocrStatus, ocrStatus) || other.ocrStatus == ocrStatus));
}


@override
int get hashCode => Object.hash(runtimeType,id,imagePath,index,text,ocrStatus);

@override
String toString() {
  return 'DocumentPage(id: $id, imagePath: $imagePath, index: $index, text: $text, ocrStatus: $ocrStatus)';
}


}

/// @nodoc
abstract mixin class $DocumentPageCopyWith<$Res>  {
  factory $DocumentPageCopyWith(DocumentPage value, $Res Function(DocumentPage) _then) = _$DocumentPageCopyWithImpl;
@useResult
$Res call({
 String id, String imagePath, int index, String text, OcrStatus ocrStatus
});




}
/// @nodoc
class _$DocumentPageCopyWithImpl<$Res>
    implements $DocumentPageCopyWith<$Res> {
  _$DocumentPageCopyWithImpl(this._self, this._then);

  final DocumentPage _self;
  final $Res Function(DocumentPage) _then;

/// Create a copy of DocumentPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? imagePath = null,Object? index = null,Object? text = null,Object? ocrStatus = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,imagePath: null == imagePath ? _self.imagePath : imagePath // ignore: cast_nullable_to_non_nullable
as String,index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,ocrStatus: null == ocrStatus ? _self.ocrStatus : ocrStatus // ignore: cast_nullable_to_non_nullable
as OcrStatus,
  ));
}

}


/// Adds pattern-matching-related methods to [DocumentPage].
extension DocumentPagePatterns on DocumentPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DocumentPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DocumentPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DocumentPage value)  $default,){
final _that = this;
switch (_that) {
case _DocumentPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DocumentPage value)?  $default,){
final _that = this;
switch (_that) {
case _DocumentPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String imagePath,  int index,  String text,  OcrStatus ocrStatus)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DocumentPage() when $default != null:
return $default(_that.id,_that.imagePath,_that.index,_that.text,_that.ocrStatus);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String imagePath,  int index,  String text,  OcrStatus ocrStatus)  $default,) {final _that = this;
switch (_that) {
case _DocumentPage():
return $default(_that.id,_that.imagePath,_that.index,_that.text,_that.ocrStatus);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String imagePath,  int index,  String text,  OcrStatus ocrStatus)?  $default,) {final _that = this;
switch (_that) {
case _DocumentPage() when $default != null:
return $default(_that.id,_that.imagePath,_that.index,_that.text,_that.ocrStatus);case _:
  return null;

}
}

}

/// @nodoc


class _DocumentPage extends DocumentPage {
  const _DocumentPage({required this.id, required this.imagePath, required this.index, this.text = '', this.ocrStatus = OcrStatus.pending}): super._();
  

@override final  String id;
/// Relative path to the page JPEG, e.g. `documents/<docId>/page_001.jpg`.
@override final  String imagePath;
/// Zero-based position within the parent document.
@override final  int index;
/// Text recognised on this page. Empty until OCR runs.
@override@JsonKey() final  String text;
@override@JsonKey() final  OcrStatus ocrStatus;

/// Create a copy of DocumentPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DocumentPageCopyWith<_DocumentPage> get copyWith => __$DocumentPageCopyWithImpl<_DocumentPage>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DocumentPage&&(identical(other.id, id) || other.id == id)&&(identical(other.imagePath, imagePath) || other.imagePath == imagePath)&&(identical(other.index, index) || other.index == index)&&(identical(other.text, text) || other.text == text)&&(identical(other.ocrStatus, ocrStatus) || other.ocrStatus == ocrStatus));
}


@override
int get hashCode => Object.hash(runtimeType,id,imagePath,index,text,ocrStatus);

@override
String toString() {
  return 'DocumentPage(id: $id, imagePath: $imagePath, index: $index, text: $text, ocrStatus: $ocrStatus)';
}


}

/// @nodoc
abstract mixin class _$DocumentPageCopyWith<$Res> implements $DocumentPageCopyWith<$Res> {
  factory _$DocumentPageCopyWith(_DocumentPage value, $Res Function(_DocumentPage) _then) = __$DocumentPageCopyWithImpl;
@override @useResult
$Res call({
 String id, String imagePath, int index, String text, OcrStatus ocrStatus
});




}
/// @nodoc
class __$DocumentPageCopyWithImpl<$Res>
    implements _$DocumentPageCopyWith<$Res> {
  __$DocumentPageCopyWithImpl(this._self, this._then);

  final _DocumentPage _self;
  final $Res Function(_DocumentPage) _then;

/// Create a copy of DocumentPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? imagePath = null,Object? index = null,Object? text = null,Object? ocrStatus = null,}) {
  return _then(_DocumentPage(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,imagePath: null == imagePath ? _self.imagePath : imagePath // ignore: cast_nullable_to_non_nullable
as String,index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,ocrStatus: null == ocrStatus ? _self.ocrStatus : ocrStatus // ignore: cast_nullable_to_non_nullable
as OcrStatus,
  ));
}


}

// dart format on
