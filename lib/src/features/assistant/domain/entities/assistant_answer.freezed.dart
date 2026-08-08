// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'assistant_answer.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AnswerCitation {

 String get documentId;/// Denormalised so the citation chip renders without a repository read.
/// A rename leaves this stale until the next answer, which is acceptable
/// for a transcript — it records what the document was called at the time.
 String get documentTitle; int get pageIndex; String get snippet;/// Question terms this passage actually contained, so the citation can
/// show *why* it was cited rather than only where it came from.
 List<String> get matchedTerms;/// Score relative to the best passage in the same answer, 0–1. Comparable
/// within one answer only, exactly like the BM25 scores beneath it.
 double get relevance;
/// Create a copy of AnswerCitation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AnswerCitationCopyWith<AnswerCitation> get copyWith => _$AnswerCitationCopyWithImpl<AnswerCitation>(this as AnswerCitation, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AnswerCitation&&(identical(other.documentId, documentId) || other.documentId == documentId)&&(identical(other.documentTitle, documentTitle) || other.documentTitle == documentTitle)&&(identical(other.pageIndex, pageIndex) || other.pageIndex == pageIndex)&&(identical(other.snippet, snippet) || other.snippet == snippet)&&const DeepCollectionEquality().equals(other.matchedTerms, matchedTerms)&&(identical(other.relevance, relevance) || other.relevance == relevance));
}


@override
int get hashCode => Object.hash(runtimeType,documentId,documentTitle,pageIndex,snippet,const DeepCollectionEquality().hash(matchedTerms),relevance);

@override
String toString() {
  return 'AnswerCitation(documentId: $documentId, documentTitle: $documentTitle, pageIndex: $pageIndex, snippet: $snippet, matchedTerms: $matchedTerms, relevance: $relevance)';
}


}

/// @nodoc
abstract mixin class $AnswerCitationCopyWith<$Res>  {
  factory $AnswerCitationCopyWith(AnswerCitation value, $Res Function(AnswerCitation) _then) = _$AnswerCitationCopyWithImpl;
@useResult
$Res call({
 String documentId, String documentTitle, int pageIndex, String snippet, List<String> matchedTerms, double relevance
});




}
/// @nodoc
class _$AnswerCitationCopyWithImpl<$Res>
    implements $AnswerCitationCopyWith<$Res> {
  _$AnswerCitationCopyWithImpl(this._self, this._then);

  final AnswerCitation _self;
  final $Res Function(AnswerCitation) _then;

/// Create a copy of AnswerCitation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? documentId = null,Object? documentTitle = null,Object? pageIndex = null,Object? snippet = null,Object? matchedTerms = null,Object? relevance = null,}) {
  return _then(_self.copyWith(
documentId: null == documentId ? _self.documentId : documentId // ignore: cast_nullable_to_non_nullable
as String,documentTitle: null == documentTitle ? _self.documentTitle : documentTitle // ignore: cast_nullable_to_non_nullable
as String,pageIndex: null == pageIndex ? _self.pageIndex : pageIndex // ignore: cast_nullable_to_non_nullable
as int,snippet: null == snippet ? _self.snippet : snippet // ignore: cast_nullable_to_non_nullable
as String,matchedTerms: null == matchedTerms ? _self.matchedTerms : matchedTerms // ignore: cast_nullable_to_non_nullable
as List<String>,relevance: null == relevance ? _self.relevance : relevance // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [AnswerCitation].
extension AnswerCitationPatterns on AnswerCitation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AnswerCitation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AnswerCitation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AnswerCitation value)  $default,){
final _that = this;
switch (_that) {
case _AnswerCitation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AnswerCitation value)?  $default,){
final _that = this;
switch (_that) {
case _AnswerCitation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String documentId,  String documentTitle,  int pageIndex,  String snippet,  List<String> matchedTerms,  double relevance)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AnswerCitation() when $default != null:
return $default(_that.documentId,_that.documentTitle,_that.pageIndex,_that.snippet,_that.matchedTerms,_that.relevance);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String documentId,  String documentTitle,  int pageIndex,  String snippet,  List<String> matchedTerms,  double relevance)  $default,) {final _that = this;
switch (_that) {
case _AnswerCitation():
return $default(_that.documentId,_that.documentTitle,_that.pageIndex,_that.snippet,_that.matchedTerms,_that.relevance);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String documentId,  String documentTitle,  int pageIndex,  String snippet,  List<String> matchedTerms,  double relevance)?  $default,) {final _that = this;
switch (_that) {
case _AnswerCitation() when $default != null:
return $default(_that.documentId,_that.documentTitle,_that.pageIndex,_that.snippet,_that.matchedTerms,_that.relevance);case _:
  return null;

}
}

}

/// @nodoc


class _AnswerCitation extends AnswerCitation {
  const _AnswerCitation({required this.documentId, required this.documentTitle, required this.pageIndex, required this.snippet, final  List<String> matchedTerms = const <String>[], this.relevance = 0.0}): _matchedTerms = matchedTerms,super._();
  

@override final  String documentId;
/// Denormalised so the citation chip renders without a repository read.
/// A rename leaves this stale until the next answer, which is acceptable
/// for a transcript — it records what the document was called at the time.
@override final  String documentTitle;
@override final  int pageIndex;
@override final  String snippet;
/// Question terms this passage actually contained, so the citation can
/// show *why* it was cited rather than only where it came from.
 final  List<String> _matchedTerms;
/// Question terms this passage actually contained, so the citation can
/// show *why* it was cited rather than only where it came from.
@override@JsonKey() List<String> get matchedTerms {
  if (_matchedTerms is EqualUnmodifiableListView) return _matchedTerms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_matchedTerms);
}

/// Score relative to the best passage in the same answer, 0–1. Comparable
/// within one answer only, exactly like the BM25 scores beneath it.
@override@JsonKey() final  double relevance;

/// Create a copy of AnswerCitation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AnswerCitationCopyWith<_AnswerCitation> get copyWith => __$AnswerCitationCopyWithImpl<_AnswerCitation>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AnswerCitation&&(identical(other.documentId, documentId) || other.documentId == documentId)&&(identical(other.documentTitle, documentTitle) || other.documentTitle == documentTitle)&&(identical(other.pageIndex, pageIndex) || other.pageIndex == pageIndex)&&(identical(other.snippet, snippet) || other.snippet == snippet)&&const DeepCollectionEquality().equals(other._matchedTerms, _matchedTerms)&&(identical(other.relevance, relevance) || other.relevance == relevance));
}


@override
int get hashCode => Object.hash(runtimeType,documentId,documentTitle,pageIndex,snippet,const DeepCollectionEquality().hash(_matchedTerms),relevance);

@override
String toString() {
  return 'AnswerCitation(documentId: $documentId, documentTitle: $documentTitle, pageIndex: $pageIndex, snippet: $snippet, matchedTerms: $matchedTerms, relevance: $relevance)';
}


}

/// @nodoc
abstract mixin class _$AnswerCitationCopyWith<$Res> implements $AnswerCitationCopyWith<$Res> {
  factory _$AnswerCitationCopyWith(_AnswerCitation value, $Res Function(_AnswerCitation) _then) = __$AnswerCitationCopyWithImpl;
@override @useResult
$Res call({
 String documentId, String documentTitle, int pageIndex, String snippet, List<String> matchedTerms, double relevance
});




}
/// @nodoc
class __$AnswerCitationCopyWithImpl<$Res>
    implements _$AnswerCitationCopyWith<$Res> {
  __$AnswerCitationCopyWithImpl(this._self, this._then);

  final _AnswerCitation _self;
  final $Res Function(_AnswerCitation) _then;

/// Create a copy of AnswerCitation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? documentId = null,Object? documentTitle = null,Object? pageIndex = null,Object? snippet = null,Object? matchedTerms = null,Object? relevance = null,}) {
  return _then(_AnswerCitation(
documentId: null == documentId ? _self.documentId : documentId // ignore: cast_nullable_to_non_nullable
as String,documentTitle: null == documentTitle ? _self.documentTitle : documentTitle // ignore: cast_nullable_to_non_nullable
as String,pageIndex: null == pageIndex ? _self.pageIndex : pageIndex // ignore: cast_nullable_to_non_nullable
as int,snippet: null == snippet ? _self.snippet : snippet // ignore: cast_nullable_to_non_nullable
as String,matchedTerms: null == matchedTerms ? _self._matchedTerms : matchedTerms // ignore: cast_nullable_to_non_nullable
as List<String>,relevance: null == relevance ? _self.relevance : relevance // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc
mixin _$AssistantAnswer {

 String get text; List<AnswerCitation> get citations; AnswerSource get source; AnswerKind get kind;/// Set only when a question was answered — [AnswerKind.grounded], or
/// [AnswerKind.extraction] where the shape found stands in for coverage.
///
/// Null everywhere else. Nothing was found to be confident about, and a
/// summary answers no question, so there is no coverage to report.
 AnswerConfidence? get confidence;/// How many documents were read to produce this. Shown so an answer drawn
/// from one document out of forty does not look like the whole library
/// agreed with it.
 int get documentsSearched;
/// Create a copy of AssistantAnswer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AssistantAnswerCopyWith<AssistantAnswer> get copyWith => _$AssistantAnswerCopyWithImpl<AssistantAnswer>(this as AssistantAnswer, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssistantAnswer&&(identical(other.text, text) || other.text == text)&&const DeepCollectionEquality().equals(other.citations, citations)&&(identical(other.source, source) || other.source == source)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.confidence, confidence) || other.confidence == confidence)&&(identical(other.documentsSearched, documentsSearched) || other.documentsSearched == documentsSearched));
}


@override
int get hashCode => Object.hash(runtimeType,text,const DeepCollectionEquality().hash(citations),source,kind,confidence,documentsSearched);

@override
String toString() {
  return 'AssistantAnswer(text: $text, citations: $citations, source: $source, kind: $kind, confidence: $confidence, documentsSearched: $documentsSearched)';
}


}

/// @nodoc
abstract mixin class $AssistantAnswerCopyWith<$Res>  {
  factory $AssistantAnswerCopyWith(AssistantAnswer value, $Res Function(AssistantAnswer) _then) = _$AssistantAnswerCopyWithImpl;
@useResult
$Res call({
 String text, List<AnswerCitation> citations, AnswerSource source, AnswerKind kind, AnswerConfidence? confidence, int documentsSearched
});




}
/// @nodoc
class _$AssistantAnswerCopyWithImpl<$Res>
    implements $AssistantAnswerCopyWith<$Res> {
  _$AssistantAnswerCopyWithImpl(this._self, this._then);

  final AssistantAnswer _self;
  final $Res Function(AssistantAnswer) _then;

/// Create a copy of AssistantAnswer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? text = null,Object? citations = null,Object? source = null,Object? kind = null,Object? confidence = freezed,Object? documentsSearched = null,}) {
  return _then(_self.copyWith(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,citations: null == citations ? _self.citations : citations // ignore: cast_nullable_to_non_nullable
as List<AnswerCitation>,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as AnswerSource,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as AnswerKind,confidence: freezed == confidence ? _self.confidence : confidence // ignore: cast_nullable_to_non_nullable
as AnswerConfidence?,documentsSearched: null == documentsSearched ? _self.documentsSearched : documentsSearched // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [AssistantAnswer].
extension AssistantAnswerPatterns on AssistantAnswer {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AssistantAnswer value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AssistantAnswer() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AssistantAnswer value)  $default,){
final _that = this;
switch (_that) {
case _AssistantAnswer():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AssistantAnswer value)?  $default,){
final _that = this;
switch (_that) {
case _AssistantAnswer() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String text,  List<AnswerCitation> citations,  AnswerSource source,  AnswerKind kind,  AnswerConfidence? confidence,  int documentsSearched)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AssistantAnswer() when $default != null:
return $default(_that.text,_that.citations,_that.source,_that.kind,_that.confidence,_that.documentsSearched);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String text,  List<AnswerCitation> citations,  AnswerSource source,  AnswerKind kind,  AnswerConfidence? confidence,  int documentsSearched)  $default,) {final _that = this;
switch (_that) {
case _AssistantAnswer():
return $default(_that.text,_that.citations,_that.source,_that.kind,_that.confidence,_that.documentsSearched);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String text,  List<AnswerCitation> citations,  AnswerSource source,  AnswerKind kind,  AnswerConfidence? confidence,  int documentsSearched)?  $default,) {final _that = this;
switch (_that) {
case _AssistantAnswer() when $default != null:
return $default(_that.text,_that.citations,_that.source,_that.kind,_that.confidence,_that.documentsSearched);case _:
  return null;

}
}

}

/// @nodoc


class _AssistantAnswer extends AssistantAnswer {
  const _AssistantAnswer({required this.text, final  List<AnswerCitation> citations = const <AnswerCitation>[], this.source = AnswerSource.retrieval, this.kind = AnswerKind.grounded, this.confidence, this.documentsSearched = 0}): _citations = citations,super._();
  

@override final  String text;
 final  List<AnswerCitation> _citations;
@override@JsonKey() List<AnswerCitation> get citations {
  if (_citations is EqualUnmodifiableListView) return _citations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_citations);
}

@override@JsonKey() final  AnswerSource source;
@override@JsonKey() final  AnswerKind kind;
/// Set only when a question was answered — [AnswerKind.grounded], or
/// [AnswerKind.extraction] where the shape found stands in for coverage.
///
/// Null everywhere else. Nothing was found to be confident about, and a
/// summary answers no question, so there is no coverage to report.
@override final  AnswerConfidence? confidence;
/// How many documents were read to produce this. Shown so an answer drawn
/// from one document out of forty does not look like the whole library
/// agreed with it.
@override@JsonKey() final  int documentsSearched;

/// Create a copy of AssistantAnswer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AssistantAnswerCopyWith<_AssistantAnswer> get copyWith => __$AssistantAnswerCopyWithImpl<_AssistantAnswer>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AssistantAnswer&&(identical(other.text, text) || other.text == text)&&const DeepCollectionEquality().equals(other._citations, _citations)&&(identical(other.source, source) || other.source == source)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.confidence, confidence) || other.confidence == confidence)&&(identical(other.documentsSearched, documentsSearched) || other.documentsSearched == documentsSearched));
}


@override
int get hashCode => Object.hash(runtimeType,text,const DeepCollectionEquality().hash(_citations),source,kind,confidence,documentsSearched);

@override
String toString() {
  return 'AssistantAnswer(text: $text, citations: $citations, source: $source, kind: $kind, confidence: $confidence, documentsSearched: $documentsSearched)';
}


}

/// @nodoc
abstract mixin class _$AssistantAnswerCopyWith<$Res> implements $AssistantAnswerCopyWith<$Res> {
  factory _$AssistantAnswerCopyWith(_AssistantAnswer value, $Res Function(_AssistantAnswer) _then) = __$AssistantAnswerCopyWithImpl;
@override @useResult
$Res call({
 String text, List<AnswerCitation> citations, AnswerSource source, AnswerKind kind, AnswerConfidence? confidence, int documentsSearched
});




}
/// @nodoc
class __$AssistantAnswerCopyWithImpl<$Res>
    implements _$AssistantAnswerCopyWith<$Res> {
  __$AssistantAnswerCopyWithImpl(this._self, this._then);

  final _AssistantAnswer _self;
  final $Res Function(_AssistantAnswer) _then;

/// Create a copy of AssistantAnswer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? text = null,Object? citations = null,Object? source = null,Object? kind = null,Object? confidence = freezed,Object? documentsSearched = null,}) {
  return _then(_AssistantAnswer(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,citations: null == citations ? _self._citations : citations // ignore: cast_nullable_to_non_nullable
as List<AnswerCitation>,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as AnswerSource,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as AnswerKind,confidence: freezed == confidence ? _self.confidence : confidence // ignore: cast_nullable_to_non_nullable
as AnswerConfidence?,documentsSearched: null == documentsSearched ? _self.documentsSearched : documentsSearched // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
