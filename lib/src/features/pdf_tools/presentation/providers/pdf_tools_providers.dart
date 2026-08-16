import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/storage_paths.dart';
import '../../../documents/presentation/providers/document_providers.dart';
import '../../data/repositories/pdf_tools_repository_impl.dart';
import '../../domain/repositories/pdf_tools_repository.dart';
import '../../domain/usecases/compress_document.dart';
import '../../domain/usecases/merge_pdfs.dart';

final pdfToolsRepositoryProvider = Provider<PdfToolsRepository>(
  (ref) => PdfToolsRepositoryImpl(
    documents: ref.watch(documentRepositoryProvider),
    paths: ref.watch(storagePathsProvider),
  ),
);

final pickPdfProvider = Provider<PickPdf>(
  (ref) => PickPdf(ref.watch(pdfToolsRepositoryProvider)),
);

final mergePdfsProvider = Provider<MergePdfs>(
  (ref) => MergePdfs(ref.watch(pdfToolsRepositoryProvider)),
);

final compressDocumentProvider = Provider<CompressDocument>(
  (ref) => CompressDocument(ref.watch(pdfToolsRepositoryProvider)),
);

final compressPdfFileProvider = Provider<CompressPdfFile>(
  (ref) => CompressPdfFile(ref.watch(pdfToolsRepositoryProvider)),
);
