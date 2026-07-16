import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';

import '../../Services/VaultAuthGate.dart';
import '../../Services/VaultDatabaseService.dart';
import '../../Services/VaultImportService.dart';
import '../../theme/app_theme.dart';
import 'vault_item.dart';
import 'vault_photo_viewer.dart';
import 'vault_video_player.dart';

/// شاشة "الخزنة" — معرض الصور والفيديوهات المشفرة.
///
/// الشاشة كلها محمية ببوابة بيومترية [VaultAuthGate] (بصمة/Face ID +
/// FLAG_SECURE لمنع screenshot + إعادة مصادقة عند العودة من الخلفية).
/// المحتوى نفسه (ثامبنيلز) بييجي من قاعدة بيانات SQLCipher مشفّرة
/// بالكامل عن طريق [VaultDatabaseService]، بصفحات (lazy pagination)
/// مش كل الصفوف مرة واحدة.
class VaultScreen extends StatelessWidget {
  const VaultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return VaultAuthGate(
      builder: (context) => const _VaultGalleryContent(),
    );
  }
}

class _VaultGalleryContent extends StatefulWidget {
  const _VaultGalleryContent();

  @override
  State<_VaultGalleryContent> createState() => _VaultGalleryContentState();
}

class _VaultGalleryContentState extends State<_VaultGalleryContent> {
  static const _pageSize = 30;

  final ScrollController _scrollController = ScrollController();
  final List<VaultItem> _items = [];

  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _importing = false;
  String? _loadError;

  // ---------------------------------------------------------------------
  // Toast + debug helpers
  // ---------------------------------------------------------------------

  void _debug(String msg) {
    debugPrint('[VaultScreen][DEBUG] $msg');
  }

  void _toastSuccess(String msg) {
    _debug('SUCCESS: $msg');
    Fluttertoast.showToast(
      msg: msg,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.green,
      textColor: Colors.white,
    );
  }

  void _toastError(String msg) {
    _debug('ERROR: $msg');
    Fluttertoast.showToast(
      msg: msg,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.redAccent,
      textColor: Colors.white,
    );
  }

  void _toastWarning(String msg) {
    _debug('WARNING: $msg');
    Fluttertoast.showToast(
      msg: msg,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.orange,
      textColor: Colors.white,
    );
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    // بنقفل الاتصال بقاعدة البيانات المشفّرة وقت الخروج من الشاشة.
    VaultDatabaseService.close();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    _debug('بدء تحميل الصفحة الأولى من الخزنة');
    setState(() {
      _initialLoading = true;
      _loadError = null;
    });
    try {
      final page =
      await VaultDatabaseService.fetchPage(limit: _pageSize, offset: 0);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page);
        _hasMore = page.length == _pageSize;
        _initialLoading = false;
      });
      _debug('اتحمّل ${page.length} عنصر في الصفحة الأولى');
    } catch (e, st) {
      _debug('فشل تحميل الصفحة الأولى: $e\n$st');
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _loadError = '$e';
      });
      _toastError('تعذّر تحميل محتوى الخزنة');
    }
  }

  Future<void> _loadMore() async {
    _debug('بدء تحميل صفحة إضافية، offset = ${_items.length}');
    setState(() => _loadingMore = true);
    try {
      final page = await VaultDatabaseService.fetchPage(
        limit: _pageSize,
        offset: _items.length,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length == _pageSize;
        _loadingMore = false;
      });
      _debug('اتحمّل ${page.length} عنصر إضافي');
    } catch (e, st) {
      _debug('فشل تحميل صفحة إضافية: $e\n$st');
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _toastWarning('تعذّر تحميل المزيد من العناصر');
    }
  }

  /// دي بتشتغل من ساعة ما المستخدم يدوس زرار "+" في الـ AppBar.
  Future<void> _importFile() async {
    _debug('المستخدم دوس على زرار استيراد ملف .enc');

    try {
      _debug('بفتح الـ file picker...');
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['enc'],
      );

      if (result == null) {
        // المستخدم لغى الاختيار فعلًا.
        _debug('المستخدم لغى اختيار الملف');
        return;
      }

      _debug('المستخدم اختار: ${result.files.single.name}');

      if (result.files.single.path == null) {
        // ده مش إلغاء من المستخدم - بيحصل غالبًا في أندرويد لما الملف
        // بييجي من مزوّد مستندات (Google Drive، بعض تطبيقات الملفات)
        // وبيرجّع content:// URI مش مسار حقيقي على القرص، فـ file_picker
        // بيرجّع path == null.
        _debug('path == null: الملف جاي من مزوّد مستندات (content:// URI)');
        _toastError(
          'تعذّر الوصول لمسار الملف مباشرة. جرّب تختار الملف من '
              'تطبيق "الملفات" بدل مزوّدات التخزين السحابي، أو انسخ '
              'الملف لتخزين الجهاز المحلي الأول.',
        );
        return;
      }

      final pickedPath = result.files.single.path!;
      _debug('مسار الملف المختار: $pickedPath');

      setState(() => _importing = true);
      _debug('بدء عملية الاستيراد الفعلية عن طريق VaultImportService...');

      final item = await VaultImportService.importEncFile(pickedPath);
      _debug('نجحت عملية الاستيراد، id الملف الجديد = ${item.id}, نوعه = ${item.type}');

      if (!mounted) return;
      setState(() {
        _items.insert(0, item);
        _importing = false;
      });

      _toastSuccess(
        item.type == VaultItemType.photo
            ? 'اتضافت الصورة للخزنة بنجاح'
            : 'اتضاف الفيديو للخزنة بنجاح',
      );
    } catch (e, st) {
      _debug('فشلت عملية الاستيراد: $e\n$st');
      if (!mounted) return;
      setState(() => _importing = false);
      _toastError('تعذّر استيراد الملف: $e');
    }
  }

  void _openItem(VaultItem item) {
    _debug('فتح عنصر: id = ${item.id}, نوعه = ${item.type}');
    if (item.type == VaultItemType.video) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => VaultVideoPlayerScreen(videoItem: item),
      ));
      return;
    }

    final photoItems =
    _items.where((i) => i.type == VaultItemType.photo).toList();
    final index = photoItems.indexOf(item);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VaultPhotoViewer(
        photoItems: photoItems,
        initialIndex: index < 0 ? 0 : index,
      ),
    ));
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;

    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    if (date.year == now.year) {
      return DateFormat.MMMM('ar').format(date);
    }
    return DateFormat.yMMMM('ar').format(date);
  }

  /// بتجمّع الـ items المحمّلة حاليًا لمجموعات حسب هيدر التاريخ، مع
  /// الحفاظ على ترتيب الأحدث للأقدم اللي جاي من قاعدة البيانات نفسها.
  List<_DateGroup> _buildGroups() {
    final groups = <_DateGroup>[];
    for (final item in _items) {
      final label = _dateLabel(item.dateCreated);
      if (groups.isNotEmpty && groups.last.label == label) {
        groups.last.items.add(item);
      } else {
        groups.add(_DateGroup(label, [item]));
      }
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text(
          "الخزنة",
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_importing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.add_rounded, color: AppColors.primary),
              onPressed: _importFile,
              tooltip: 'استيراد ملف .enc',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initialLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _loadError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Text(
          "لا يوجد محتوى بعد",
          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
      );
    }

    final groups = _buildGroups();

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadInitial,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          for (final group in groups) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  group.label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 3,
                  mainAxisSpacing: 3,
                ),
                delegate: SliverChildBuilderDelegate(
                      (context, index) => _VaultGridCell(
                    item: group.items[index],
                    onTap: () => _openItem(group.items[index]),
                  ),
                  childCount: group.items.length,
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator(
                    color: AppColors.primary)
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateGroup {
  final String label;
  final List<VaultItem> items;
  _DateGroup(this.label, this.items);
}

/// خلية واحدة في الـ grid: ثامبنيل من الذاكرة (Image.memory)، مع أيقونة
/// تشغيل ومدة للفيديو.
class _VaultGridCell extends StatelessWidget {
  final VaultItem item;
  final VoidCallback onTap;

  const _VaultGridCell({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              item.thumbnailBlob,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
            if (item.type == VaultItemType.video) ...[
              const Positioned(
                top: 4,
                left: 4,
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  color: Colors.white,
                  size: 20,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.formattedDuration,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}