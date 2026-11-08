import 'dart:async';

import 'package:flutter/material.dart';

import '../models/car.dart';

enum _CatalogFilter {
  all,
  popular,
  iran,
  suv,
  pickup,
  motorcycle,
  truck,
  bus,
  tractor,
  heavy,
}

extension on _CatalogFilter {
  String get label => switch (this) {
        _CatalogFilter.all => 'همه',
        _CatalogFilter.popular => 'محبوب',
        _CatalogFilter.iran => 'بازار ایران',
        _CatalogFilter.suv => 'شاسی‌بلند',
        _CatalogFilter.pickup => 'وانت',
        _CatalogFilter.motorcycle => 'موتورسیکلت',
        _CatalogFilter.truck => 'کامیون',
        _CatalogFilter.bus => 'اتوبوس',
        _CatalogFilter.tractor => 'تراکتور',
        _CatalogFilter.heavy => 'ماشین‌آلات سنگین',
      };

  IconData get icon => switch (this) {
        _CatalogFilter.all => Icons.apps_rounded,
        _CatalogFilter.popular => Icons.star_rounded,
        _CatalogFilter.iran => Icons.flag_rounded,
        _CatalogFilter.suv => Icons.directions_car_filled_rounded,
        _CatalogFilter.pickup => Icons.local_shipping_outlined,
        _CatalogFilter.motorcycle => Icons.two_wheeler_rounded,
        _CatalogFilter.truck => Icons.local_shipping_rounded,
        _CatalogFilter.bus => Icons.directions_bus_rounded,
        _CatalogFilter.tractor => Icons.agriculture_rounded,
        _CatalogFilter.heavy => Icons.precision_manufacturing_rounded,
      };
}

IconData _vehicleIconFor(CarCategory? category) {
  return switch (category) {
    CarCategory.motorcycle || CarCategory.scooter => Icons.two_wheeler_rounded,
    CarCategory.atv => Icons.sports_motorsports_rounded,
    CarCategory.truck => Icons.local_shipping_rounded,
    CarCategory.bus || CarCategory.minibus => Icons.directions_bus_rounded,
    CarCategory.tractor => Icons.agriculture_rounded,
    CarCategory.heavy => Icons.precision_manufacturing_rounded,
    CarCategory.pickup => Icons.local_shipping_outlined,
    CarCategory.van => Icons.airport_shuttle_rounded,
    CarCategory.suv => Icons.directions_car_filled_rounded,
    _ => Icons.directions_car_rounded,
  };
}

bool _isCommercial(CarCategory? category) {
  return category == CarCategory.motorcycle ||
      category == CarCategory.scooter ||
      category == CarCategory.atv ||
      category == CarCategory.truck ||
      category == CarCategory.bus ||
      category == CarCategory.minibus ||
      category == CarCategory.tractor ||
      category == CarCategory.heavy;
}

/// blobهای نرمال‌شده یک‌بار ساخته می‌شوند تا هر keystroke کل لیست را
/// با normalizeSearch دوباره پردازش نکند.
class _CarCatalogIndex {
  final List<Car> cars;
  final List<String> searchBlobs;
  final List<int> popularIndices;
  final Map<_CatalogFilter, List<int>> filterBuckets;

  _CarCatalogIndex._({
    required this.cars,
    required this.searchBlobs,
    required this.popularIndices,
    required this.filterBuckets,
  });

  factory _CarCatalogIndex.build(List<Car> cars) {
    final blobs = List<String>.generate(
      cars.length,
      (i) => Car.normalizeSearch(cars[i].searchBlob),
      growable: false,
    );

    final popular = <int>[];
    final buckets = <_CatalogFilter, List<int>>{
      for (final f in _CatalogFilter.values) f: <int>[],
    };

    for (var i = 0; i < cars.length; i++) {
      final car = cars[i];
      buckets[_CatalogFilter.all]!.add(i);
      if (car.isPopular) {
        popular.add(i);
        buckets[_CatalogFilter.popular]!.add(i);
      }
      if (car.region == 'ایران' && !_isCommercial(car.category)) {
        buckets[_CatalogFilter.iran]!.add(i);
      }
      final cat = car.category;
      if (cat == CarCategory.suv) buckets[_CatalogFilter.suv]!.add(i);
      if (cat == CarCategory.pickup) buckets[_CatalogFilter.pickup]!.add(i);
      if (cat == CarCategory.motorcycle ||
          cat == CarCategory.scooter ||
          cat == CarCategory.atv) {
        buckets[_CatalogFilter.motorcycle]!.add(i);
      }
      if (cat == CarCategory.truck) buckets[_CatalogFilter.truck]!.add(i);
      if (cat == CarCategory.bus || cat == CarCategory.minibus) {
        buckets[_CatalogFilter.bus]!.add(i);
      }
      if (cat == CarCategory.tractor) buckets[_CatalogFilter.tractor]!.add(i);
      if (cat == CarCategory.heavy) buckets[_CatalogFilter.heavy]!.add(i);
    }

    return _CarCatalogIndex._(
      cars: cars,
      searchBlobs: blobs,
      popularIndices: popular,
      filterBuckets: buckets,
    );
  }

  List<Car> query({
    required _CatalogFilter filter,
    required String rawQuery,
  }) {
    final indices = filterBuckets[filter] ?? const <int>[];
    final q = Car.normalizeSearch(rawQuery.trim());
    if (q.isEmpty) {
      return List<Car>.generate(indices.length, (i) => cars[indices[i]]);
    }

    final out = <Car>[];
    for (final i in indices) {
      if (searchBlobs[i].contains(q)) {
        out.add(cars[i]);
      }
    }
    return out;
  }

  List<Car> get popularCars =>
      List<Car>.generate(popularIndices.length, (i) => cars[popularIndices[i]]);
}

class CarSelectorWidget extends StatelessWidget {
  final List<Car> cars;
  final Car? selectedCar;
  final bool isLoading;
  final bool hasError;
  final VoidCallback onRetry;
  final ValueChanged<Car> onCarSelected;

  const CarSelectorWidget({
    super.key,
    required this.cars,
    required this.selectedCar,
    required this.isLoading,
    required this.hasError,
    required this.onRetry,
    required this.onCarSelected,
  });

  Future<void> _openSheet(BuildContext context) async {
    final result = await showModalBottomSheet<Car>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CarSearchSheet(
        cars: cars,
        selectedCar: selectedCar,
      ),
    );
    if (result != null) {
      onCarSelected(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isLoading) return _ShimmerBox(theme: theme);
    if (hasError && cars.isEmpty) {
      return _ErrorBox(onRetry: onRetry, theme: theme);
    }
    if (cars.isEmpty) return _EmptyBox(theme: theme);

    final bool isSelected = selectedCar != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openSheet(context),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.secondary.withOpacity(0.6)
                  : theme.dividerColor,
              width: isSelected ? 1.5 : 1.0,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.secondary.withOpacity(0.12)
                      : theme.dividerColor.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _vehicleIconFor(selectedCar?.category),
                  color:
                      isSelected ? theme.colorScheme.secondary : theme.hintColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedCar?.fullName ??
                          'انتخاب خودرو، موتور یا ماشین‌آلات...',
                      style: TextStyle(
                        color: isSelected
                            ? theme.textTheme.bodyLarge?.color
                            : theme.hintColor,
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (isSelected && selectedCar!.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        selectedCar!.description,
                        style: TextStyle(color: theme.hintColor, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded,
                    color: theme.colorScheme.secondary, size: 18)
              else
                Icon(Icons.keyboard_arrow_down_rounded, color: theme.hintColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarSearchSheet extends StatefulWidget {
  final List<Car> cars;
  final Car? selectedCar;

  const _CarSearchSheet({required this.cars, required this.selectedCar});

  @override
  State<_CarSearchSheet> createState() => _CarSearchSheetState();
}

class _CarSearchSheetState extends State<_CarSearchSheet> {
  static const int _pageSize = 60;

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _debounce;

  late final _CarCatalogIndex _index;

  List<Car> _filtered = const [];
  List<dynamic> _visibleItems = const [];
  int _visibleCarCount = 0;
  bool _hasMore = false;

  String _query = '';
  _CatalogFilter _filter = _CatalogFilter.all;

  @override
  void initState() {
    super.initState();
    _index = _CarCatalogIndex.build(widget.cars);
    _filtered = _index.query(filter: _filter, rawQuery: '');
    _rebuildVisible(reset: true);
    _searchCtrl.addListener(_onSearchChanged);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || !_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  void _onSearchChanged() {
    final newQuery = _searchCtrl.text;
    if (_query == newQuery) return;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      _applyFilter(newQuery);
    });

    if (mounted && (_query.isEmpty) != (newQuery.isEmpty)) {
      setState(() => _query = newQuery);
    }
  }

  void _applyFilter(String query) {
    final next = _index.query(filter: _filter, rawQuery: query);
    setState(() {
      _query = query;
      _filtered = next;
      _rebuildVisible(reset: true);
    });
  }

  void _setFilter(_CatalogFilter filter) {
    if (_filter == filter) return;
    _filter = filter;
    _applyFilter(_searchCtrl.text);
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _applyFilter('');
  }

  void _selectCar(Car car) => Navigator.pop(context, car);

  void _rebuildVisible({required bool reset}) {
    if (reset) {
      _visibleCarCount = 0;
      _visibleItems = const [];
    }

    final qEmpty = _query.trim().isEmpty;
    final List<Car> source;
    final bool groupByBrand;

    if (qEmpty && _filter == _CatalogFilter.all) {
      groupByBrand = true;
      source = _filtered.where((c) => !c.isPopular).toList(growable: false);
    } else if (qEmpty) {
      groupByBrand = true;
      source = _filtered;
    } else {
      groupByBrand = false;
      source = _filtered;
    }

    final totalCars = qEmpty && _filter == _CatalogFilter.all
        ? source.length + _index.popularCars.length
        : source.length;

    final targetCars = (_visibleCarCount + _pageSize) < totalCars
        ? _visibleCarCount + _pageSize
        : totalCars;

    final items = <dynamic>[];
    var carsAdded = 0;

    if (qEmpty && _filter == _CatalogFilter.all) {
      final popular = _index.popularCars;
      if (popular.isNotEmpty) {
        items.add('⭐ محبوب‌ترین‌ها');
        for (final car in popular) {
          if (carsAdded >= targetCars) break;
          items.add(car);
          carsAdded++;
        }
        if (carsAdded < targetCars && source.isNotEmpty) {
          items.add('divider');
        }
      }
      if (carsAdded < targetCars) {
        final remaining = targetCars - carsAdded;
        final slice = source.take(remaining).toList(growable: false);
        items.addAll(_brandGroupedItems(slice));
        carsAdded += slice.length;
      }
      _hasMore = carsAdded < (popular.length + source.length);
    } else if (groupByBrand) {
      final slice = source.take(targetCars).toList(growable: false);
      items.addAll(_brandGroupedItems(slice));
      carsAdded = slice.length;
      _hasMore = carsAdded < source.length;
    } else {
      final slice = source.take(targetCars).toList(growable: false);
      items.addAll(slice);
      carsAdded = slice.length;
      _hasMore = carsAdded < source.length;
    }

    _visibleCarCount = carsAdded;
    _visibleItems = items;
  }

  void _loadMore() {
    if (!_hasMore) return;
    setState(() => _rebuildVisible(reset: false));
  }

  List<dynamic> _brandGroupedItems(List<Car> cars) {
    if (cars.isEmpty) return const [];
    final grouped = <String, List<Car>>{};
    for (final car in cars) {
      grouped.putIfAbsent(car.brand, () => <Car>[]).add(car);
    }
    final brands = grouped.keys.toList()..sort();
    final items = <dynamic>[];
    for (final brand in brands) {
      items.add(brand);
      items.addAll(grouped[brand]!);
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topPad = MediaQuery.of(context).padding.top + kToolbarHeight;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(top: topPad),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: theme.canvasColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _buildHandle(theme),
          _buildHeader(theme),
          _buildSearchField(theme),
          _buildFilterChips(theme),
          const Divider(height: 1),
          Expanded(child: _buildList(theme)),
        ],
      ),
    );
  }

  Widget _buildHandle(ThemeData theme) => Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        height: 4,
        width: 40,
        decoration: BoxDecoration(
          color: theme.dividerColor,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Row(
        children: [
          Icon(Icons.two_wheeler_rounded,
              color: theme.colorScheme.secondary, size: 22),
          const SizedBox(width: 8),
          Text(
            'انتخاب وسیله نقلیه',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (_query.trim().isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_filtered.length} نتیجه',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        style: TextStyle(color: theme.textTheme.bodyLarge?.color),
        decoration: InputDecoration(
          hintText: 'جستجو (پراید، دنا، هوندا ۱۲۵، تراکتور ۲۸۵، ...)',
          hintStyle: TextStyle(color: theme.hintColor, fontSize: 13),
          prefixIcon: Icon(Icons.search_rounded, color: theme.hintColor),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: _clearSearch,
                )
              : null,
          filled: true,
          fillColor: theme.cardColor,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: theme.dividerColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide:
                BorderSide(color: theme.colorScheme.secondary, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips(ThemeData theme) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        scrollDirection: Axis.horizontal,
        itemCount: _CatalogFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _CatalogFilter.values[index];
          final selected = _filter == filter;
          return FilterChip(
            visualDensity: VisualDensity.compact,
            selected: selected,
            showCheckmark: false,
            avatar: Icon(
              filter.icon,
              size: 16,
              color: selected ? theme.colorScheme.onSecondary : theme.hintColor,
            ),
            label: Text(filter.label, style: const TextStyle(fontSize: 12)),
            selectedColor: theme.colorScheme.secondary,
            labelStyle: TextStyle(
              color: selected
                  ? theme.colorScheme.onSecondary
                  : theme.textTheme.bodyMedium?.color,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
            onSelected: (_) => _setFilter(filter),
          );
        },
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    if (_filtered.isEmpty) return _buildNoResult(theme);

    final extra = _hasMore ? 1 : 0;

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _visibleItems.length + extra,
      itemBuilder: (context, index) {
        if (index >= _visibleItems.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ),
          );
        }

        final item = _visibleItems[index];
        if (item is String) {
          if (item == 'divider') return const Divider(height: 8);
          return _buildSectionHeader(item, theme);
        }
        if (item is Car) return _buildCarTile(item, theme);
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: theme.hintColor,
        ),
      ),
    );
  }

  Widget _buildCarTile(Car car, ThemeData theme) {
    final isSelected = widget.selectedCar?.id == car.id;
    final query = _query.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectCar(car),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.secondary.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(
                    color: theme.colorScheme.secondary.withOpacity(0.3))
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.secondary.withOpacity(0.15)
                      : theme.cardColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _vehicleIconFor(car.category),
                  color: isSelected
                      ? theme.colorScheme.secondary
                      : theme.hintColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHighlightedText(
                      car.fullName,
                      query,
                      theme,
                      isSelected: isSelected,
                    ),
                    if (car.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        car.description,
                        style: TextStyle(fontSize: 11, color: theme.hintColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (car.isPopular && query.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'محبوب',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (isSelected)
                Icon(
                  Icons.check_circle_rounded,
                  color: theme.colorScheme.secondary,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedText(
    String text,
    String query,
    ThemeData theme, {
    bool isSelected = false,
  }) {
    if (query.isEmpty) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected
              ? theme.colorScheme.secondary
              : theme.textTheme.bodyLarge?.color,
        ),
      );
    }

    final nQuery = Car.normalizeSearch(query);
    final nText = Car.normalizeSearch(text);
    final idx = nText.indexOf(nQuery);
    if (idx < 0 || nText.length != text.length) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected
              ? theme.colorScheme.secondary
              : theme.textTheme.bodyLarge?.color,
        ),
      );
    }

    final matchLen = nQuery.length;
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 14, color: theme.textTheme.bodyLarge?.color),
        children: [
          TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, idx + matchLen),
            style: TextStyle(
              backgroundColor: theme.colorScheme.secondary.withOpacity(0.25),
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: text.substring(idx + matchLen)),
        ],
      ),
    );
  }

  Widget _buildNoResult(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: theme.hintColor.withOpacity(0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'وسیله‌ای با نام "$_query" یافت نشد.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.hintColor, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'برند، مدل، موتورسیکلت یا ماشین‌آلات را با نام دیگری جستجو کنید.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.hintColor.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  final ThemeData theme;
  const _ShimmerBox({required this.theme});

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
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
      builder: (context, _) {
        final t = _ctrl.value;
        return Container(
          height: 56,
          decoration: BoxDecoration(
            color: Color.lerp(
              widget.theme.cardColor,
              widget.theme.dividerColor.withOpacity(0.4),
              t,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final VoidCallback onRetry;
  final ThemeData theme;
  const _ErrorBox({required this.onRetry, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.redAccent, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'خطا در بارگذاری لیست وسایل نقلیه',
              style: TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('تلاش مجدد'),
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  final ThemeData theme;
  const _EmptyBox({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: theme.hintColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'لیست وسایل نقلیه خالی است. صفحه را بکشید تا دوباره بارگذاری شود.',
              style: TextStyle(color: theme.hintColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
