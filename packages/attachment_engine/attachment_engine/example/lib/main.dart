import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter/material.dart';

import 'config_demo_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AttachmentManager.initializeDefault();
  runApp(const AttachmentEngineExampleApp());
}

class AttachmentEngineExampleApp extends StatelessWidget {
  const AttachmentEngineExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attachment Engine Example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const AttachmentListPage(),
    );
  }
}

/// Sample attachments pointing at small, publicly-reachable network
/// resources so this example doubles as a manual real-flow validation of
/// the resolve -> cache -> download -> render pipeline.
final sampleAttachments = <Attachment>[
  Attachment(
    id: 'sample-image',
    name: 'Sample Image (network)',
    extension: 'jpg',
    mimeType: 'image/jpeg',
    remoteUrl:
        'https://upload.wikimedia.org/wikipedia/commons/a/a3/June_odd-eyed-cat.jpg',
    source: const AttachmentSource.url(
      'https://upload.wikimedia.org/wikipedia/commons/a/a3/June_odd-eyed-cat.jpg',
    ),
    attachmentType: AttachmentType.image,
  ),
  Attachment(
    id: 'sample-pdf',
    name: 'Sample PDF (network)',
    extension: 'pdf',
    mimeType: 'application/pdf',
    remoteUrl:
        'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
    source: const AttachmentSource.url(
      'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
    ),
    attachmentType: AttachmentType.pdf,
  ),
  Attachment(
    id: 'sample-video',
    name: 'Sample MP4 (network)',
    extension: 'mp4',
    mimeType: 'video/mp4',
    remoteUrl:
        'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4',
    source: const AttachmentSource.url(
      'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4',
    ),
    attachmentType: AttachmentType.video,
  ),
  Attachment(
    id: 'sample-audio',
    name: 'Sample MP3 (network)',
    extension: 'mp3',
    mimeType: 'audio/mpeg',
    remoteUrl: 'https://download.samplelib.com/mp3/sample-9s.mp3',
    source: const AttachmentSource.url(
      'https://download.samplelib.com/mp3/sample-9s.mp3',
    ),
    attachmentType: AttachmentType.audio,
  ),
];

class AttachmentListPage extends StatelessWidget {
  const AttachmentListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attachment Engine Example'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'AttachmentEngineConfig demo',
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ConfigDemoPage()));
            },
          ),
        ],
      ),
      body: AttachmentList(
        attachments: sampleAttachments,
        onTapAttachment: (attachment) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AttachmentDetailPage(attachment: attachment),
            ),
          );
        },
      ),
    );
  }
}

/// Resolves the tapped attachment (download/cache as needed) and then
/// shows it via [AttachmentViewer], demonstrating the full pipeline.
class AttachmentDetailPage extends StatefulWidget {
  const AttachmentDetailPage({super.key, required this.attachment});

  final Attachment attachment;

  @override
  State<AttachmentDetailPage> createState() => _AttachmentDetailPageState();
}

class _AttachmentDetailPageState extends State<AttachmentDetailPage> {
  late Future<ResolvedAttachment> _future;

  @override
  void initState() {
    super.initState();
    _future = AttachmentManager.instance.open(widget.attachment);
  }

  void _retry() {
    setState(() {
      _future = AttachmentManager.instance.retry(widget.attachment);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.attachment.name)),
      body: FutureBuilder<ResolvedAttachment>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            final failure = error is AttachmentResolutionException
                ? error.failure
                : const UnknownFailure();
            return AttachmentErrorView(failure: failure, onRetry: _retry);
          }
          final resolved = snapshot.data!;
          return AttachmentViewer(
            attachment: resolved.attachment,
            registry: AttachmentManager.instance.rendererRegistry,
          );
        },
      ),
    );
  }
}
