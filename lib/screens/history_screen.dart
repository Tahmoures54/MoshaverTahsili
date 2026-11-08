import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/share_service.dart';
import '../models/diagnostic.dart';
import 'result_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  List<Diagnostic>? _history;
  List<Diagnostic>? _filteredHistory;
  String? _error;
  bool _isLoading = false;

  final _searchController = TextEditingController();
  bool _isSearching = false;

  late final AnimationController _listAnimCtrl;

  @override
  void initState() {
    super.initState();
    _listAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchHistory());
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _listAnimCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (_history == null) return;

    setState(() {
      if (query.isEmpty) {
        _filteredHistory = List.from(_history!);
      } else {
        _filteredHistory = _history!.where((item) {
          final carMatch = (item.carName ?? item.carId).toLowerCase().contains(query);
          final descMatch = (item.description ?? '').toLowerCase().contains(query);
          return carMatch || descMatch;
        }).toList();
      }
    });
  }

  Future<void> _fetchHistory() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated || auth.token == null) {
      if (!mounted) return;
      setState(() {
        _error = 'برای مشاهده تاریخچه ابتدا وارد حساب کاربری خود شوید.';
        _isLoading = false;
      });
      return;
    }

    try {
      final api = context.read<ApiService>();
      final history = await api.getHistory(auth.token!);
      if (!mounted) return;

      setState(() {
        _history = history;
        _filteredHistory = List.from(history);
        _isLoading = false;
      });

      unawaited(_listAnimCtrl.forward(from: 0));
    } catch (e) {
      debugPrint('Error fetching history: $e');
      if (!mounted) return;
      setState(() {
        _error = 'خطا در دریافت اطلاعات. لطفاً اتصال اینترنت خود را بررسی کرده و دوباره تلاش کنید.';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteItem(Diagnostic item, int filteredIndex) async {
    final auth = context.read<AuthProvider>();
    if (auth.token == null) return;

    final originalIndex = _history!.indexOf(item);

    setState(() {
      _filteredHistory!.removeAt(filteredIndex);
      _history!.remove(item);
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    final snack = messenger.showSnackBar(
      SnackBar(
        content: const Text('آیتم حذف شد'),
        action: SnackBarAction(
          label: 'بازگشت',
          onPressed: () {
            _history!.insert(originalIndex, item);
            _onSearchChanged();
          },
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );

    final result = await snack.closed;
    if (result != SnackBarClosedReason.action && mounted) {
      try {
        await context.read<ApiService>().deleteHistory(auth.token!, item.id);
      } catch (_) {
        if (mounted) {
          setState(() {
            _history!.insert(originalIndex, item);
            _onSearchChanged();
          });
          messenger.showSnackBar(
            SnackBar(
              content: const Text('خطا در حذف. آیتم بازگردانده شد.'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: theme.colorScheme.onPrimary),
                decoration: InputDecoration(
                  hintText: 'جستجو در تاریخچه...',
                  hintStyle: TextStyle(color: theme.colorScheme.onPrimary.withOpacity(0.6)),
                  border: InputBorder.none,
                ),
              )
            : const Text('تاریخچه عیب‌یابی', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: !_isSearching,
        elevation: 0,
        backgroundColor: theme.appBarTheme.backgroundColor ?? theme.primaryColor,
        actions: [
          if (_history != null && _history!.isNotEmpty)
            IconButton(
              icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
              tooltip: _isSearching ? 'بستن جستجو' : 'جستجو',
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchController.clear();
                    _filteredHistory = List.from(_history!);
                  }
                });
              },
            ),
          if (!_isSearching)
            IconButton(
              icon: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.refresh_rounded),
              tooltip: 'بارگذاری مجدد',
              onPressed: _isLoading ? null : _fetchHistory,
            ),
        ],
      ),
      body: SafeArea(child: _buildBody(theme)),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading && _history == null) return _buildLoadingShimmer(theme);
    if (_error != null && _history == null) return _buildErrorState(theme);
    if (_history != null && _history!.isEmpty) return _buildEmptyState(theme);

    if (_filteredHistory != null) {
      return RefreshIndicator(
        color: theme.colorScheme.secondary,
        onRefresh: _fetchHistory,
        child: Column(
          children: [
            if (_isSearching && _searchController.text.isNotEmpty)
              _buildSearchResultBanner(theme),
            Expanded(
              child: _filteredHistory!.isEmpty
                  ? _buildNoSearchResult(theme)
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: _filteredHistory!.length,
                      itemBuilder: (context, index) {
                        return _buildHistoryItem(_filteredHistory![index], index, theme);
                      },
                    ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildHistoryItem(Diagnostic item, int index, ThemeData theme) {
    final intervalBegin = (index * 0.1).clamp(0.0, 0.8);
    final intervalEnd = (intervalBegin + 0.3).clamp(0.0, 1.0);
    final curve = CurvedAnimation(
      parent: _listAnimCtrl,
      curve: Interval(intervalBegin, intervalEnd, curve: Curves.easeOut),
    );

    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(curve),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Dismissible(
            key: ValueKey(item.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('حذف', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  SizedBox(width: 8),
                  Icon(Icons.delete_outline_rounded, color: Colors.white),
                ],
              ),
            ),
            confirmDismiss: (_) async => await _showDeleteConfirmDialog(item),
            onDismissed: (_) => unawaited(_deleteItem(item, index)),
            child: _buildItemCard(item, index, theme),
          ),
        ),
      ),
    );
  }

  Widget _buildItemCard(Diagnostic item, int index, ThemeData theme) {
    final isGolden = item.isGolden;
    final carLabel = item.carName ?? item.carId;
    final formattedDate = _formatDate(item.createdAt);

    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isGolden ? Colors.amber.withOpacity(0.4) : theme.dividerColor.withOpacity(0.5),
          width: isGolden ? 1.5 : 1,
        ),
      ),
      color: theme.cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ResultScreen(resultText: item.result)));
        },
        onLongPress: () => _showItemOptions(item, index),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isGolden ? Colors.amber.withOpacity(0.15) : theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.directions_car_rounded,
                      color: isGolden ? Colors.amber.shade600 : theme.colorScheme.primary,
                      size: 28,
                    ),
                  ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            carLabel,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isGolden) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.amber.withOpacity(0.4)),
                            ),
                            child: const Text('⭐ طلایی', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.description ?? 'بدون توضیحات',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.textTheme.bodySmall?.color?.withOpacity(0.8), fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    if (formattedDate != null)
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded, size: 12, color: theme.hintColor),
                          const SizedBox(width: 4),
                          Text(formattedDate, style: TextStyle(fontSize: 11, color: theme.hintColor)),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (item.result != null && item.result!.trim().isNotEmpty)
                IconButton(
                  tooltip: 'اشتراک‌گذاری پاسخ',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    ShareService.shareDiagnosis(
                      result: item.result!,
                      carName: item.carName,
                      year: item.carYear,
                      referralCode: context.read<AuthProvider>().referralCode,
                    );
                  },
                  icon: Icon(
                    Icons.share_rounded,
                    size: 20,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: theme.hintColor.withOpacity(0.4)),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _showDeleteConfirmDialog(Diagnostic item) {
    final theme = Theme.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: theme.dialogBackgroundColor,
        title: const Text('حذف تاریخچه'),
        content: Text('آیا مطمئن هستید که می‌خواهید این عیب‌یابی را حذف کنید؟', style: theme.textTheme.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  void _showItemOptions(Diagnostic item, int index) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      backgroundColor: theme.cardColor,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: theme.dividerColor, borderRadius: BorderRadius.circular(2)),
              ),
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('مشاهده نتیجه'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ResultScreen(resultText: item.result)));
                },
              ),
              if (item.result != null && item.result!.trim().isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.share_rounded),
                  title: const Text('اشتراک‌گذاری پاسخ'),
                  onTap: () {
                    Navigator.pop(ctx);
                    ShareService.shareDiagnosis(
                      result: item.result!,
                      carName: item.carName,
                      year: item.carYear,
                      referralCode: context.read<AuthProvider>().referralCode,
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text('حذف', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirm = await _showDeleteConfirmDialog(item);
                  if (confirm == true && mounted) {
                    unawaited(_deleteItem(item, index));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.secondary.withOpacity(0.08),
      child: Text(
        '${_filteredHistory!.length} نتیجه یافت شد',
        style: TextStyle(color: theme.colorScheme.secondary, fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildNoSearchResult(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: theme.hintColor.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('نتیجه‌ای یافت نشد', style: TextStyle(color: theme.hintColor, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('عبارت دیگری را جستجو کنید', style: TextStyle(color: theme.hintColor, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: theme.colorScheme.error.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(Icons.wifi_off_rounded, color: theme.colorScheme.error, size: 48),
            ),
            const SizedBox(height: 24),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 15, height: 1.6),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: theme.colorScheme.secondary,
                foregroundColor: theme.colorScheme.onSecondary,
              ),
              onPressed: _fetchHistory,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('تلاش مجدد', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 80, color: theme.hintColor.withOpacity(0.25)),
            const SizedBox(height: 20),
            Text('هنوز عیب‌یابی ثبت نشده', style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'اولین عیب‌یابی خودروی خود را انجام دهید\nو نتیجه آن اینجا ذخیره می‌شود.',
              style: TextStyle(color: theme.hintColor, fontSize: 13, height: 1.6),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingShimmer(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: 5,
      itemBuilder: (_, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _ShimmerCard(theme: theme),
      ),
    );
  }

  String? _formatDate(DateTime? date) {
    if (date == null) return null;
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}  '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _ShimmerCard extends StatefulWidget {
  final ThemeData theme;
  const _ShimmerCard({required this.theme});

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Opacity(
          opacity: 0.5 + (_ctrl.value * 0.5),
          child: Container(
            height: 90,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: widget.theme.dividerColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: widget.theme.dividerColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        height: 14,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: widget.theme.dividerColor,
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 11,
                        width: 160,
                        decoration: BoxDecoration(
                          color: widget.theme.dividerColor,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
