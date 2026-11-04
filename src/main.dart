import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PDF Maker By Arun',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.red, useMaterial3: true),
        home: const HomeScreen(),
      );
}

// ---------- helpers ----------
class PageItem {
  final File file;
  int turns;
  PageItem(this.file, [this.turns = 0]);
}

Future<Directory> pdfDir() async {
  final base = await getApplicationDocumentsDirectory();
  final d = Directory('${base.path}/PDFMakerByArun');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

Future<File> saveBytes(Uint8List bytes, String name, {bool overwrite = false}) async {
  final d = await pdfDir();
  var clean = name.trim().replaceAll(RegExp(r'[^\w\- ]'), '').trim();
  if (clean.isEmpty) clean = 'PDF_${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
  var f = File('${d.path}/$clean.pdf');
  var n = 1;
  while (!overwrite && await f.exists()) {
    f = File('${d.path}/${clean}_${n++}.pdf');
  }
  await f.writeAsBytes(bytes);
  return f;
}

Future<String?> askName(BuildContext c, String def) {
  final ctrl = TextEditingController(text: def);
  return showDialog<String>(
    context: c,
    builder: (_) => AlertDialog(
      title: const Text('PDF ka naam'),
      content: TextField(controller: ctrl, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Save')),
      ],
    ),
  );
}

Future<Uint8List> buildPdf(List<PageItem> pages) async {
  final doc = pw.Document();
  for (final p in pages) {
    final img = pw.MemoryImage(await p.file.readAsBytes());
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(12),
      build: (_) => pw.Center(
        child: pw.Transform.rotateBox(
          angle: -(p.turns % 4) * math.pi / 2,
          child: pw.Image(img, fit: pw.BoxFit.contain),
        ),
      ),
    ));
  }
  return doc.save();
}

Future<Uint8List> mergePdfs(List<File> files) async {
  final doc = pw.Document();
  for (final f in files) {
    final bytes = await f.readAsBytes();
    await for (final r in Printing.raster(bytes, dpi: 150)) {
      final img = pw.MemoryImage(await r.toPng());
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(r.width * 72 / 150, r.height * 72 / 150),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(img, fit: pw.BoxFit.fill),
      ));
    }
  }
  return doc.save();
}

Future<List<PageItem>> pdfToPages(File f) async {
  final tmp = await getTemporaryDirectory();
  final out = <PageItem>[];
  var i = 0;
  await for (final r in Printing.raster(await f.readAsBytes(), dpi: 120)) {
    final file = File('${tmp.path}/e_${DateTime.now().microsecondsSinceEpoch}_${i++}.png');
    await file.writeAsBytes(await r.toPng());
    out.add(PageItem(file));
  }
  return out;
}

Future<void> openPdf(File f) async => Printing.layoutPdf(
      onLayout: (_) => f.readAsBytes(),
      name: f.path.split('/').last,
    );

void msg(BuildContext c, String t, {File? open}) {
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(
    content: Text(t),
    action: open == null ? null : SnackBarAction(label: 'Open', onPressed: () => openPdf(open)),
  ));
}

// ---------- home ----------
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Widget tile(BuildContext c, IconData i, String t, String s, VoidCallback f) => Card(
        child: ListTile(
          leading: Icon(i, size: 36, color: Theme.of(c).colorScheme.primary),
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(s),
          contentPadding: const EdgeInsets.all(16),
          onTap: f,
        ),
      );

  Future<void> go(BuildContext c, Widget w) async {
    final r = await Navigator.push(c, MaterialPageRoute(builder: (_) => w));
    if (r is File && c.mounted) msg(c, 'PDF save ho gaya', open: r);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('PDF Maker By Arun')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          tile(context, Icons.camera_alt, 'Camera se PDF', 'Photo kheencho, PDF banao',
              () => go(context, const CreatorScreen(autoCamera: true))),
          tile(context, Icons.photo_library, 'Gallery se PDF', 'Photos chuno, PDF banao',
              () => go(context, const CreatorScreen(autoGallery: true))),
          tile(context, Icons.merge_type, 'Merge PDF', 'Kai PDF ko ek me jodo',
              () => go(context, const MergeScreen())),
          tile(context, Icons.folder, 'Meri PDFs', 'Open, edit, share, delete',
              () => go(context, const MyPdfsScreen())),
        ]),
      );
}

// ---------- create / edit ----------
class CreatorScreen extends StatefulWidget {
  final List<PageItem> initial;
  final String? name;
  final bool autoCamera, autoGallery;
  const CreatorScreen({super.key, this.initial = const [], this.name, this.autoCamera = false, this.autoGallery = false});
  @override
  State<CreatorScreen> createState() => _CreatorScreenState();
}

class _CreatorScreenState extends State<CreatorScreen> {
  late final List<PageItem> pages = List.of(widget.initial);
  final picker = ImagePicker();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoCamera) WidgetsBinding.instance.addPostFrameCallback((_) => camera());
    if (widget.autoGallery) WidgetsBinding.instance.addPostFrameCallback((_) => gallery());
  }

  Future<void> camera() async {
    final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 2000);
    if (x != null) setState(() => pages.add(PageItem(File(x.path))));
  }

  Future<void> gallery() async {
    final xs = await picker.pickMultiImage(imageQuality: 80, maxWidth: 2000);
    if (xs.isNotEmpty) setState(() => pages.addAll(xs.map((x) => PageItem(File(x.path)))));
  }

  Future<void> save() async {
    if (pages.isEmpty) return;
    final def = widget.name ?? 'PDF_${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final name = await askName(context, def);
    if (name == null) return;
    setState(() => busy = true);
    try {
      final f = await saveBytes(await buildPdf(pages), name, overwrite: widget.name != null);
      if (mounted) Navigator.pop(context, f);
    } catch (e) {
      if (mounted) msg(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Bahar jaana hai?'),
        content: const Text('Save nahi kiya, pages hat jayenge.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Ruko')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Haan')),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: pages.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Pages (${pages.length})'),
          actions: [IconButton(icon: const Icon(Icons.check), tooltip: 'Save PDF', onPressed: busy ? null : save)],
        ),
        body: busy
            ? const Center(child: CircularProgressIndicator())
            : pages.isEmpty
                ? const Center(child: Text('Neeche se photo add karo'))
                : ReorderableListView.builder(
                    itemCount: pages.length,
                    onReorder: (o, n) {
                      if (n > o) n--;
                      setState(() => pages.insert(n, pages.removeAt(o)));
                    },
                    itemBuilder: (_, i) {
                      final p = pages[i];
                      return ListTile(
                        key: ObjectKey(p),
                        leading: SizedBox(
                          width: 60,
                          height: 80,
                          child: RotatedBox(
                            quarterTurns: p.turns % 4,
                            child: Image.file(p.file, cacheWidth: 200, fit: BoxFit.contain),
                          ),
                        ),
                        title: Text('Page ${i + 1}'),
                        subtitle: const Text('Pakad ke upar-neeche karo'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: const Icon(Icons.rotate_right), onPressed: () => setState(() => p.turns++)),
                          IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() => pages.removeAt(i))),
                        ]),
                      );
                    },
                  ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: FilledButton.icon(onPressed: camera, icon: const Icon(Icons.camera_alt), label: const Text('Camera'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.tonalIcon(onPressed: gallery, icon: const Icon(Icons.photo), label: const Text('Gallery'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(onPressed: busy ? null : save, icon: const Icon(Icons.picture_as_pdf), label: const Text('Save'))),
            ]),
          ),
        ),
      ));
}

// ---------- merge ----------
class MergeScreen extends StatefulWidget {
  const MergeScreen({super.key});
  @override
  State<MergeScreen> createState() => _MergeScreenState();
}

class _MergeScreenState extends State<MergeScreen> {
  final List<File> files = [];
  bool busy = false;

  Future<void> add() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: true);
    if (r == null) return;
    setState(() => files.addAll(r.paths.whereType<String>().map((p) => File(p))));
  }

  Future<void> merge() async {
    if (files.length < 2) {
      msg(context, 'Kam se kam 2 PDF chuno');
      return;
    }
    final name = await askName(context, 'Merged_${DateTime.now().millisecondsSinceEpoch ~/ 1000}');
    if (name == null) return;
    setState(() => busy = true);
    try {
      final f = await saveBytes(await mergePdfs(files), name);
      if (mounted) Navigator.pop(context, f);
    } catch (e) {
      if (mounted) msg(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Merge PDF (${files.length})')),
        body: busy
            ? const Center(child: CircularProgressIndicator())
            : files.isEmpty
                ? const Center(child: Text('PDF add karo'))
                : ReorderableListView.builder(
                    itemCount: files.length,
                    onReorder: (o, n) {
                      if (n > o) n--;
                      setState(() => files.insert(n, files.removeAt(o)));
                    },
                    itemBuilder: (_, i) => ListTile(
                      key: ObjectKey(files[i]),
                      leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                      title: Text(files[i].path.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => files.removeAt(i))),
                    ),
                  ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: FilledButton.tonalIcon(onPressed: add, icon: const Icon(Icons.add), label: const Text('Add PDF'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(onPressed: busy ? null : merge, icon: const Icon(Icons.merge_type), label: const Text('Merge'))),
            ]),
          ),
        ),
      );
}

// ---------- my pdfs ----------
class MyPdfsScreen extends StatefulWidget {
  const MyPdfsScreen({super.key});
  @override
  State<MyPdfsScreen> createState() => _MyPdfsScreenState();
}

class _MyPdfsScreenState extends State<MyPdfsScreen> {
  Future<List<File>> load() async {
    final d = await pdfDir();
    final l = d.listSync().whereType<File>().where((f) => f.path.endsWith('.pdf')).toList();
    l.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return l;
  }

  Future<void> edit(File f) async {
    msg(context, 'Pages load ho rahe hain...');
    final pages = await pdfToPages(f);
    if (!mounted) return;
    final name = f.path.split('/').last.replaceAll('.pdf', '');
    final r = await Navigator.push(context, MaterialPageRoute(builder: (_) => CreatorScreen(initial: pages, name: name)));
    if (r is File && mounted) msg(context, 'PDF update ho gaya', open: r);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Meri PDFs')),
        body: FutureBuilder<List<File>>(
          future: load(),
          builder: (_, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final l = s.data!;
            if (l.isEmpty) return const Center(child: Text('Abhi koi PDF nahi'));
            return ListView.builder(
              itemCount: l.length,
              itemBuilder: (_, i) {
                final f = l[i];
                return ListTile(
                  leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  title: Text(f.path.split('/').last),
                  subtitle: Text('${(f.lengthSync() / 1024).toStringAsFixed(0)} KB'),
                  onTap: () => openPdf(f),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'share') await Share.shareXFiles([XFile(f.path)]);
                      if (v == 'edit') await edit(f);
                      if (v == 'delete') {
                        await f.delete();
                        setState(() {});
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit pages')),
                      PopupMenuItem(value: 'share', child: Text('Share')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                );
              },
            );
          },
        ),
      );
}
