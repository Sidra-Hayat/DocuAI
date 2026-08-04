// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'search_hit.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SearchHit {

 Document get document;/// BM25 relevance. Comparable only within one result set — an absolute
/// score means nothing on its own, so never show it to the user.
 double get score;/// Matching passages, most relevant first. Empty when the query matched the
/// title but no page text.
 List<SearchSnippet> get snippets;
/// Create a copy of SearchHit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SearchHitCopyWith<SearchHit> get copyWith => _$SearchHitCopyWithImpl<SearchHit>(this as SearchHit, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SearchHit&&(identical(other.document, document) || other.document == document)&&(identical(other.score, score) || other.score == score)&&const DeepCollectionEquality().equals(other.snippets, snippets));
}


@override
int get hashCode => Object.hash(runtimeType,document,score,const DeepCollectionEquality().hash(snippets));

@override
String toString() {
  return 'SearchHit(document: $document, score: $score, snippets: $snippets)';
}


}

/// @nodoc
abstract mixin class $SearchHitCopyWith<$Res>  {
  factory $SearchHitCopyWith(SearchHit value, $Res Function(SearchHit) _then) = _$SearchHitCopyWithImpl;
@useResult
$Res call({
 Document document, double score, List<SearchSnippet> snippets
});


$DocumentCopyWith<$Res> get document;

}
/// @nodoc
class _$SearchHitCopyWithImpl<$Res>
    implements $SearchHitCopyWith<$Res> {
  _$SearchHitCopyWithImpl(this._self, this._then);

  final SearchHit _self;
  final $Res Function(SearchHit) _then;

/// Create a copy of SearchHit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? document = null,Object? score = null,Object? snippets = null,}) {
  return _then(_self.copyWith(
document: null == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as Document,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double,snippets: null == snippets ? _self.snippets : snippets // ignore: cast_nullable_to_non_nullable
as List<SearchSnippet>,
  ));
}
/// Create a copy of SearchHit
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DocumentCopyWith<$Res> get document {
  
  return $DocumentCopyWith<$Res>(_self.document, (value) {
    return _then(_self.copyWith(document: value));
  });
}
}


/// Adds pattern-matching-related methods to [SearchHit].
extension SearchHitPatterns on SearchHit {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SearchHit value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SearchHit() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SearchHit value)  $default,){
final _that = this;
switch (_that) {
case _SearchHit():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SearchHit value)?  $default,){
final _that = this;
switch (_that) {
case _SearchHit() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Document document,  double score,  List<SearchSnippet> snippets)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SearchHit() when $default != null:
return $default(_that.document,_that.score,_that.snippets);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Document document,  double score,  List<SearchSnippet> snippets)  $default,) {final _that = this;
switch (_that) {
case _SearchHit():
return $default(_that.document,_that.score,_that.snippets);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Document document,  double score,  List<SearchSnippet> snippets)?  $default,) {final _that = this;
switch (_that) {
case _SearchHit() when $default != null:
return $default(_that.document,_that.score,_that.snippets);case _:
  return null;

}
}

}

/// @nodoc


class _SearchHit extends SearchHit {
  const _SearchHit({required this.document, required this.score, final  List<SearchSnippet> snippets = const <SearchSnippet>[]}): _snippets = snippets,super._();
  

@override final  Document document;
/// BM25 relevance. Comparable only within one result set — an absolute
/// score means nothing on its own, so never show it to the user.
@override final  double score;
/// Matching passages, most relevant first. Empty when the query matched the
/// title but no page text.
 final  List<SearchSnippet> _snippets;
/// Matching passages, most relevant first. Empty when the query matched the
/// title but no page text.
@override@JsonKey() List<SearchSnippet> get snippets {
  if (_snippets is EqualUnmodifiableListView) return _snippets;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_snippets);
}


/// Create a copy of SearchHit
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SearchHitCopyWith<_SearchHit> get copyWith => __$SearchHitCopyWithImpl<_SearchHit>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SearchHit&&(identical(other.document, document) || other.document == document)&&(identical(other.score, score) || other.score == score)&&const DeepCollectionEquality().equals(other._snippets, _snippets));
}


@override
int get hashCode => Object.hash(runtimeType,document,score,const DeepCollectionEquality().hash(_snippets));

@override
String toString() {
  return 'SearchHit(document: $document, score: $score, snippets: $snippets)';
}


}

/// @nodoc
abstract mixin class _$SearchHitCopyWith<$Res> implements $SearchHitCopyWith<$Res> {
  factory _$SearchHitCopyWith(_SearchHit value, $Res Function(_SearchHit) _then) = __$SearchHitCopyWithImpl;
@override @useResult
$Res call({
 Document document, double score, List<SearchSnippet> snippets
});


@override $DocumentCopyWith<$Res> get document;

}
/// @nodoc
class __$SearchHitCopyWithImpl<$Res>
    implements _$SearchHitCopyWith<$Res> {
  __$SearchHitCopyWithImpl(this._self, this._then);

  final _SearchHit _self;
  final $Res Function(_SearchHit) _then;

/// Create a copy of SearchHit
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? document = null,Object? score = null,Object? snippets = null,}) {
  return _then(_SearchHit(
document: null == document ? _self.document : document // ignore: cast_nullable_to_non_nullable
as Document,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double,snippets: null == snippets ? _self._snippets : snippets // ignore: cast_nullable_to_non_nullable
as List<SearchSnippet>,
  ));
}

/// Create a copy of SearchHit
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DocumentCopyWith<$Res> get document {
  
  return $DocumentCopyWith<$Res>(_self.document, (value) {
    return _then(_self.copyWith(document: value));
  });
}
}

/// @nodoc
mixin _$SearchSnippet {

/// Page the passage came from, zero-based.
 int get pageIndex;/// The excerpt itself, already trimmed to a displayable length.
 String get text;/// Offset of the match **within [text]**, not within the full page — the
/// snippet is what gets rendered, so the highlight must be relative to it.
 int get highlightStart; int get highlightLength;
/// Create a copy of SearchSnippet
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SearchSnippetCopyWith<SearchSnippet> get copyWith => _$SearchSnippetCopyWithImpl<SearchSnippet>(this as SearchSnippet, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SearchSnippet&&(identical(other.pageIndex, pageIndex) || other.pageIndex == pageIndex)&&(identical(other.text, text) || other.text == text)&&(identical(other.highlightStart, highlightStart) || other.highlightStart == highlightStart)&&(identical(other.highlightLength, highlightLength) || other.highlightLength == highlightLength));
}


@override
int get hashCode => Object.hash(runtimeType,pageIndex,text,highlightStart,highlightLength);

@override
String toString() {
  return 'SearchSnippet(pageIndex: $pageIndex, text: $text, highlightStart: $highlightStart, highlightLength: $highlightLength)';
}


}

/// @nodoc
abstract mixin class $SearchSnippetCopyWith<$Res>  {
  factory $SearchSnippetCopyWith(SearchSnippet value, $Res Function(SearchSnippet) _then) = _$SearchSnippetCopyWithImpl;
@useResult
$Res call({
 int pageIndex, String text, int highlightStart, int highlightLength
});




}
/// @nodoc
class _$SearchSnippetCopyWithImpl<$Res>
    implements $SearchSnippetCopyWith<$Res> {
  _$SearchSnippetCopyWithImpl(this._self, this._then);

  final SearchSnippet _self;
  final $Res Function(SearchSnippet) _then;

/// Create a copy of SearchSnippet
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pageIndex = null,Object? text = null,Object? highlightStart = null,Object? highlightLength = null,}) {
  return _then(_self.copyWith(
pageIndex: null == pageIndex ? _self.pageIndex : pageIndex // ignore: cast_nullable_to_non_nullable
as int,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,highlightStart: null == highlightStart ? _self.highlightStart : highlightStart // ignore: cast_nullable_to_non_nullable
as int,highlightLength: null == highlightLength ? _self.highlightLength : highlightLength // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [SearchSnippet].
extension SearchSnippetPatterns on SearchSnippet {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SearchSnippet value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SearchSnippet() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SearchSnippet value)  $default,){
final _that = this;
switch (_that) {
case _SearchSnippet():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SearchSnippet value)?  $default,){
final _that = this;
switch (_that) {
case _SearchSnippet() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int pageIndex,  String text,  int highlightStart,  int highlightLength)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SearchSnippet() when $default != null:
return $default(_that.pageIndex,_that.text,_that.highlightStart,_that.highlightLength);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int pageIndex,  String text,  int highlightStart,  int highlightLength)  $default,) {final _that = this;
switch (_that) {
case _SearchSnippet():
return $default(_that.pageIndex,_that.text,_that.highlightStart,_that.highlightLength);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int pageIndex,  String text,  int highlightStart,  int highlightLength)?  $default,) {final _that = this;
switch (_that) {
case _SearchSnippet() when $default != null:
return $default(_that.pageIndex,_that.text,_that.highlightStart,_that.highlightLength);case _:
  return null;

}
}

}

/// @nodoc


class _SearchSnippet extends SearchSnippet {
  const _SearchSnippet({required this.pageIndex, required this.text, required this.highlightStart, required this.highlightLength}): super._();
  

/// Page the passage came from, zero-based.
@override final  int pageIndex;
/// The excerpt itself, already trimmed to a displayable length.
@override final  String text;
/// Offset of the match **within [text]**, not within the full page — the
/// snippet is what gets rendered, so the highlight must be relative to it.
@override final  int highlightStart;
@override final  int highlightLength;

/// Create a copy of SearchSnippet
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SearchSnippetCopyWith<_SearchSnippet> get copyWith => __$SearchSnippetCopyWithImpl<_SearchSnippet>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SearchSnippet&&(identical(other.pageIndex, pageIndex) || other.pageIndex == pageIndex)&&(identical(other.text, text) || other.text == text)&&(identical(other.highlightStart, highlightStart) || other.highlightStart == highlightStart)&&(identical(other.highlightLength, highlightLength) || other.highlightLength == highlightLength));
}


@override
int get hashCode => Object.hash(runtimeType,pageIndex,text,highlightStart,highlightLength);

@override
String toString() {
  return 'SearchSnippet(pageIndex: $pageIndex, text: $text, highlightStart: $highlightStart, highlightLength: $highlightLength)';
}


}

/// @nodoc
abstract mixin class _$SearchSnippetCopyWith<$Res> implements $SearchSnippetCopyWith<$Res> {
  factory _$SearchSnippetCopyWith(_SearchSnippet value, $Res Function(_SearchSnippet) _then) = __$SearchSnippetCopyWithImpl;
@override @useResult
$Res call({
 int pageIndex, String text, int highlightStart, int highlightLength
});




}
/// @nodoc
class __$SearchSnippetCopyWithImpl<$Res>
    implements _$SearchSnippetCopyWith<$Res> {
  __$SearchSnippetCopyWithImpl(this._self, this._then);

  final _SearchSnippet _self;
  final $Res Function(_SearchSnippet) _then;

/// Create a copy of SearchSnippet
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pageIndex = null,Object? text = null,Object? highlightStart = null,Object? highlightLength = null,}) {
  return _then(_SearchSnippet(
pageIndex: null == pageIndex ? _self.pageIndex : pageIndex // ignore: cast_nullable_to_non_nullable
as int,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,highlightStart: null == highlightStart ? _self.highlightStart : highlightStart // ignore: cast_nullable_to_non_nullable
as int,highlightLength: null == highlightLength ? _self.highlightLength : highlightLength // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
