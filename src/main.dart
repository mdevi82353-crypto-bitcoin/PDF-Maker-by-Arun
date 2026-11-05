import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

// ---------- theme ----------
final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

Future<File> _themeFile() async {
  final d = await getApplicationDocumentsDirectory();
  return File('${d.path}/theme.txt');
}

Future<void> loadTheme() async {
  try {
    final f = await _themeFile();
    if (await f.exists()) {
      final s = (await f.readAsString()).trim();
      themeMode.value = s == 'dark'
          ? ThemeMode.dark
          : s == 'light'
              ? ThemeMode.light
              : ThemeMode.system;
    }
  } catch (_) {}
}

Future<void> saveTheme(ThemeMode m) async {
  themeMode.value = m;
  try {
    await (await _themeFile()).writeAsString(m == ThemeMode.dark ? 'dark' : 'light');
  } catch (_) {}
}

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF5B3DF5), brightness: b);
  final dark = b == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF0E0F14) : const Color(0xFFF6F5FB),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: scheme.onSurface,
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadTheme();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (_, mode, __) => MaterialApp(
          title: 'PDF Maker By Arun',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          home: const HomeScreen(),
        ),
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

String baseName(File f) =>
    f.path.split('/').last.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');

String kb(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).toStringAsFixed(0)} KB';

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

Future<String?> askPassword(BuildContext c) {
  final p1 = TextEditingController();
  final p2 = TextEditingController();
  String? err;
  return showDialog<String>(
    context: c,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Password set karo'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: p1, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
          const SizedBox(height: 8),
          TextField(
            controller: p2,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Dobara likho', errorText: err),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (p1.text.isEmpty) {
                setS(() => err = 'Password khaali hai');
              } else if (p1.text != p2.text) {
                setS(() => err = 'Dono password alag hain');
              } else {
                Navigator.pop(ctx, p1.text);
              }
            },
            child: const Text('Lock'),
          ),
        ],
      ),
    ),
  );
}

Future<List<File>> pickPdfs({bool multi = false}) async {
  final r = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    allowMultiple: multi,
  );
  if (r == null) return [];
  return r.paths.whereType<String>().map((p) => File(p)).toList();
}

Future<Uint8List> buildPdf(List<PageItem> pages) async {
  final doc = pw.Document();
  for (final p in pages) {
    final image = pw.MemoryImage(await p.file.readAsBytes());
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(12),
      build: (_) => pw.Center(
        child: pw.Transform.rotateBox(
          angle: -(p.turns % 4) * math.pi / 2,
          child: pw.Image(image, fit: pw.BoxFit.contain),
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
      final image = pw.MemoryImage(await r.toPng());
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(r.width * 72 / 150, r.height * 72 / 150),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
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

void msg(BuildContext c, String t, {File? open, File? share}) {
  SnackBarAction? action;
  if (open != null) {
    action = SnackBarAction(label: 'Open', onPressed: () => openPdf(open));
  } else if (share != null) {
    action = SnackBarAction(label: 'Share', onPressed: () => Share.shareXFiles([XFile(share.path)]));
  }
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t), action: action));
}

Future<void> go(BuildContext c, Widget w) async {
  final r = await Navigator.push(c, MaterialPageRoute(builder: (_) => w));
  if (r is File && c.mounted) msg(c, 'PDF save ho gaya', open: r);
}

Future<T?> runBusy<T>(BuildContext c, String text, Future<T> Function(ValueNotifier<String> status) job) async {
  final status = ValueNotifier<String>(text);
  showDialog(
    context: c,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: status,
              builder: (_, v, __) => Text(v),
            ),
          ),
        ]),
      ),
    ),
  );
  try {
    return await job(status);
  } catch (e) {
    if (c.mounted) msg(c, 'Error: $e');
    return null;
  } finally {
    if (c.mounted) Navigator.of(c, rootNavigator: true).pop();
  }
}

// ---------- tool flows ----------
Future<void> protectFlow(BuildContext c) async {
  final files = await pickPdfs();
  if (files.isEmpty || !c.mounted) return;
  final pass = await askPassword(c);
  if (pass == null || !c.mounted) return;
  final src = files.first;
  final out = await runBusy<File>(c, 'Password laga rahe hain...', (_) async {
    final doc = sf.PdfDocument(inputBytes: await src.readAsBytes());
    doc.security.userPassword = pass;
    doc.security.ownerPassword = pass;
    final saved = await doc.save();
    doc.dispose();
    return saveBytes(Uint8List.fromList(saved), '${baseName(src)}_protected');
  });
  if (out != null && c.mounted) {
    msg(c, 'Password lag gaya. Share karke dusre PDF viewer me kholo.', share: out);
  }
}

Future<void> compressFlow(BuildContext c) async {
  final files = await pickPdfs();
  if (files.isEmpty || !c.mounted) return;
  final level = await showModalBottomSheet<int>(
    context: c,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Compress level', style: TextStyle(fontWeight: FontWeight.bold))),
        ListTile(
          leading: const Icon(Icons.high_quality),
          title: const Text('Low (quality achhi)'),
          onTap: () => Navigator.pop(ctx, 0),
        ),
        ListTile(
          leading: const Icon(Icons.tune),
          title: const Text('Medium (balanced)'),
          onTap: () => Navigator.pop(ctx, 1),
        ),
        ListTile(
          leading: const Icon(Icons.compress),
          title: const Text('High (sabse chhoti file)'),
          onTap: () => Navigator.pop(ctx, 2),
        ),
      ]),
    ),
  );
  if (level == null || !c.mounted) return;
  final dpis = [130.0, 100.0, 72.0];
  final quals = [75, 55, 35];
  final src = files.first;
  final oldSize = await src.length();
  final out = await runBusy<File>(c, 'Compress ho raha hai...', (status) async {
    final doc = pw.Document();
    var n = 0;
    final dpi = dpis[level];
    await for (final r in Printing.raster(await src.readAsBytes(), dpi: dpi)) {
      n++;
      status.value = 'Page $n compress ho raha hai...';
      final decoded = img.decodePng(await r.toPng());
      if (decoded == null) throw Exception('Page padh nahi paaye');
      final jpg = img.encodeJpg(decoded, quality: quals[level]);
      final image = pw.MemoryImage(Uint8List.fromList(jpg));
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(r.width * 72 / dpi, r.height * 72 / dpi),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
      ));
      await Future.delayed(Duration.zero);
    }
    if (n == 0) throw Exception('PDF khaali ya password wali hai');
    return saveBytes(await doc.save(), '${baseName(src)}_compressed');
  });
  if (out != null && c.mounted) {
    final newSize = await out.length();
    msg(c, newSize < oldSize ? 'Size: ${kb(oldSize)} se ${kb(newSize)}' : 'Ye PDF pehle se chhoti thi (${kb(newSize)}). Higher level try karo.', open: out);
  }
}

Future<void> pdfToImagesFlow(BuildContext c) async {
  final files = await pickPdfs();
  if (files.isEmpty || !c.mounted) return;
  final src = files.first;
  final imgs = await runBusy<List<File>>(c, 'Pages image bana rahe hain...', (status) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/PDFMakerByArun_Images/${baseName(src)}_${DateTime.now().millisecondsSinceEpoch ~/ 1000}');
    await dir.create(recursive: true);
    final list = <File>[];
    var n = 0;
    await for (final r in Printing.raster(await src.readAsBytes(), dpi: 150)) {
      n++;
      status.value = 'Page $n ban raha hai...';
      final f = File('${dir.path}/page_$n.png');
      await f.writeAsBytes(await r.toPng());
      list.add(f);
    }
    if (list.isEmpty) throw Exception('PDF khaali ya password wali hai');
    return list;
  });
  if (imgs != null && c.mounted) {
    await Navigator.push(c, MaterialPageRoute(builder: (_) => ImagesScreen(files: imgs)));
  }
}

// ---------- home ----------
class Tool {
  final IconData icon;
  final String title, sub;
  final List<Color> colors;
  final VoidCallback onTap;
  Tool(this.icon, this.title, this.sub, this.colors, this.onTap);
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tools = <Tool>[
      Tool(Icons.camera_alt_rounded, 'Camera se PDF', 'Photo kheencho, PDF banao',
          const [Color(0xFFFF6B6B), Color(0xFFFF8E53)], () => go(context, const CreatorScreen(autoCamera: true))),
      Tool(Icons.image_rounded, 'Image to PDF', 'Gallery ki photos se PDF',
          const [Color(0xFF36D1DC), Color(0xFF5B86E5)], () => go(context, const CreatorScreen(autoGallery: true))),
      Tool(Icons.call_merge_rounded, 'Merge PDF', 'Kai PDF ko ek banao',
          const [Color(0xFF11998E), Color(0xFF38EF7D)], () => go(context, const MergeScreen())),
      Tool(Icons.photo_library_rounded, 'PDF to Images', 'Har page ki image',
          const [Color(0xFFF7971E), Color(0xFFFFB300)], () => pdfToImagesFlow(context)),
      Tool(Icons.lock_rounded, 'Protect PDF', 'Password laga do',
          const [Color(0xFF8E2DE2), Color(0xFF4A00E0)], () => protectFlow(context)),
      Tool(Icons.compress_rounded, 'Compress PDF', 'File size chhoti karo',
          const [Color(0xFFEE0979), Color(0xFFFF6A00)], () => compressFlow(context)),
      Tool(Icons.text_snippet_rounded, 'Copy Text', 'Image me likha text copy karo',
          const [Color(0xFF00B4DB), Color(0xFF0083B0)], () => go(context, const OcrScreen())),
      Tool(Icons.folder_rounded, 'Meri PDFs', 'Open, edit, share, delete',
          const [Color(0xFF606C88), Color(0xFF3F4C6B)], () => go(context, const MyPdfsScreen())),
    ];
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Container(
            padding: EdgeInsets.fromLTRB(22, MediaQuery.of(context).padding.top + 14, 12, 30),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: dark
                    ? const [Color(0xFF2B1B6E), Color(0xFF14151C)]
                    : const [Color(0xFF5B3DF5), Color(0xFF8E6BFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 26),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Dark / Light mode',
                  icon: Icon(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, color: Colors.white),
                  onPressed: () => saveTheme(dark ? ThemeMode.light : ThemeMode.dark),
                ),
              ]),
              const SizedBox(height: 22),
              const Text('PDF Maker', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
              const Text('By Arun', style: TextStyle(color: Colors.white70, fontSize: 18, letterSpacing: 2)),
              const SizedBox(height: 10),
              const Text('Scan  •  Merge  •  Protect  •  Compress', style: TextStyle(color: Colors.white70)),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.9,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, i) => ToolTile(tool: tools[i], cs: cs),
              childCount: tools.length,
            ),
          ),
        ),
      ]),
    );
  }
}

class ToolTile extends StatelessWidget {
  final Tool tool;
  final ColorScheme cs;
  const ToolTile({super.key, required this.tool, required this.cs});

  @override
  Widget build(BuildContext context) => Material(
        color: cs.surfaceContainerHigh,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: cs.outlineVariant, width: 0.6),
        ),
        child: InkWell(
          onTap: tool.onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: tool.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(tool.icon, color: Colors.white, size: 28),
              ),
              const Spacer(),
              Text(tool.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text(tool.sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ]),
          ),
        ),
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
        ),
      );
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
    final l = await pickPdfs(multi: true);
    if (l.isNotEmpty) setState(() => files.addAll(l));
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
      if (mounted) msg(context, 'Error: $e (password wali PDF merge nahi hoti)');
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
              Expanded(child: FilledButton.icon(onPressed: busy ? null : merge, icon: const Icon(Icons.call_merge_rounded), label: const Text('Merge'))),
            ]),
          ),
        ),
      );
}

// ---------- pdf to images result ----------
class ImagesScreen extends StatelessWidget {
  final List<File> files;
  const ImagesScreen({super.key, required this.files});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text('${files.length} Images'),
          actions: [
            IconButton(
              tooltip: 'Sab share / save karo',
              icon: const Icon(Icons.ios_share),
              onPressed: () => Share.shareXFiles(files.map((f) => XFile(f.path)).toList()),
            ),
          ],
        ),
        body: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          itemCount: files.length,
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => Share.shareXFiles([XFile(files[i].path)]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(fit: StackFit.expand, children: [
                Container(color: Colors.white),
                Image.file(files[i], cacheWidth: 500, fit: BoxFit.cover),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                    child: Text('Page ${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
              ]),
            ),
          ),
        ),
        bottomNavigationBar: const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Image pe tap karo ya upar share dabao, phir Photos / Gallery me save karo.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
}

// ---------- copy text from image (OCR) ----------
class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key});
  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  final picker = ImagePicker();
  final ctrl = TextEditingController();
  File? image;
  bool busy = false;

  Future<void> pick(ImageSource s) async {
    final x = await picker.pickImage(source: s, imageQuality: 90, maxWidth: 2500);
    if (x == null) return;
    setState(() {
      image = File(x.path);
      busy = true;
      ctrl.text = '';
    });
    final rec = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final res = await rec.processImage(InputImage.fromFilePath(x.path));
      ctrl.text = res.text;
      if (res.text.trim().isEmpty && mounted) msg(context, 'Koi text nahi mila');
    } catch (e) {
      if (mounted) msg(context, 'Error: $e');
    } finally {
      await rec.close();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Image se Text Copy')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            if (image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(height: 170, width: double.infinity, child: Image.file(image!, cacheWidth: 800, fit: BoxFit.cover)),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: busy
                  ? const Center(child: CircularProgressIndicator())
                  : TextField(
                      controller: ctrl,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText: 'Photo chuno, yahan text aa jayega. Edit bhi kar sakte ho.\n(Abhi sirf English / Latin text)',
                        border: OutlineInputBorder(),
                      ),
                    ),
            ),
          ]),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: FilledButton.tonalIcon(onPressed: () => pick(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text('Camera'))),
              const SizedBox(width: 6),
              Expanded(child: FilledButton.tonalIcon(onPressed: () => pick(ImageSource.gallery), icon: const Icon(Icons.photo), label: const Text('Gallery'))),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  if (ctrl.text.isEmpty) return;
                  await Clipboard.setData(ClipboardData(text: ctrl.text));
                  if (mounted) msg(context, 'Text copy ho gaya');
                },
              ),
              IconButton.filledTonal(
                tooltip: 'Share',
                icon: const Icon(Icons.ios_share),
                onPressed: () {
                  if (ctrl.text.isNotEmpty) Share.share(ctrl.text);
                },
              ),
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
    try {
      final pages = await pdfToPages(f);
      if (!mounted) return;
      final r = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CreatorScreen(initial: pages, name: baseName(f))),
      );
      if (r is File && mounted) msg(context, 'PDF update ho gaya', open: r);
    } catch (e) {
      if (mounted) msg(context, 'Error: $e (password wali PDF edit nahi hoti)');
    }
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
                final name = f.path.split('/').last;
                final locked = name.contains('_protected');
                return ListTile(
                  leading: Icon(locked ? Icons.lock : Icons.picture_as_pdf, color: locked ? Colors.deepPurple : Colors.red),
                  title: Text(name),
                  subtitle: Text('${locked ? 'Protected  •  ' : ''}${kb(f.lengthSync())}'),
                  onTap: () async {
                    if (locked) {
                      await Share.shareXFiles([XFile(f.path)]);
                    } else {
                      await openPdf(f);
                    }
                  },
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'share') await Share.shareXFiles([XFile(f.path)]);
                      if (v == 'edit') await edit(f);
                      if (v == 'delete') {
                        await f.delete();
                        setState(() {});
                      }
                    },
                    itemBuilder: (_) => [
                      if (!locked) const PopupMenuItem(value: 'edit', child: Text('Edit pages')),
                      const PopupMenuItem(value: 'share', child: Text('Share')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                );
              },
            );
          },
        ),
      );
}
