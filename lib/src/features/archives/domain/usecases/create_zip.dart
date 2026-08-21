import '../../../../core/error/result.dart';
import '../../../pdf_tools/domain/entities/pdf_tool_models.dart';
import '../entities/zip_build.dart';
import '../repositories/zip_builder_repository.dart';

/// Puts the chosen documents and files into one ZIP.
///
/// **One entry per thing chosen.** Six documents become six PDFs inside the
/// archive, not one six-document PDF — they are separate things that happen to
/// be travelling together, and joining them would be a merge the user did not
/// ask for. The app already offers that, separately, in the same PDF tools
/// screen this is reached from.
///
/// Thin on purpose. Everything that could be called a policy — what a document
/// turns into, what happens to a name that collides, what a cancelled run
/// leaves behind — belongs to the layer that owns the files. What is here is
/// the part that is about the *request*: that there is something to archive,
/// and that the archive has a name.
class CreateZip {
  const CreateZip(this._archives);

  final ZipBuilderRepository _archives;

  /// The name used when the user has cleared the field.
  ///
  /// Substituted rather than refused. An empty name is not a mistake worth
  /// stopping somebody for — they cleared a text field, and the archive still
  /// needs to be called something on the recipient's phone.
  static const String fallbackName = 'DocuAI archive';

  FutureResult<ZipBuildOutcome> call({
    required List<ZipSource> sources,
    required String archiveName,
    ToolProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) {
    final trimmed = archiveName.trim();

    return _archives.build(
      sources: sources,
      archiveName: trimmed.isEmpty ? fallbackName : trimmed,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }
}

/// Opens the system picker and turns what comes back into archivable sources.
///
/// A use case of its own rather than a call the screen makes on the repository,
/// so that "where files come from" stays one decision. If this app ever gains a
/// second way to choose a file, it changes here.
class PickZipFiles {
  const PickZipFiles(this._archives);

  final ZipBuilderRepository _archives;

  FutureResult<ZipSourceSelection> call() => _archives.pickFiles();
}

/// Offers a finished archive to the share sheet.
///
/// Separate from [CreateZip] because they are separate decisions for the user.
/// A build that shared automatically would put a system sheet over a result the
/// user had not read yet — and would leave somebody who only wanted the archive
/// in DocuAI having to dismiss one.
class ShareZip {
  const ShareZip(this._archives);

  final ZipBuilderRepository _archives;

  FutureResult<void> call(ZipBuildOutcome outcome) =>
      _archives.share(outcome.path);
}
