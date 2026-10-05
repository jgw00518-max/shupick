import 'package:flutter/material.dart';
import '../../app/store_controller.dart';
import '../../domain/models.dart';
import '../localization.dart';

/// Loads each product's actual color-size combinations for a cart row.
class CartItemOptions extends StatefulWidget {
  const CartItemOptions({
    super.key,
    required this.item,
    required this.store,
    required this.onChanged,
  });
  final CartItem item;
  final StoreController store;
  final ValueChanged<ProductOption> onChanged;
  @override
  State<CartItemOptions> createState() => _CartItemOptionsState();
}

class _CartItemOptionsState extends State<CartItemOptions> {
  List<ProductOption> options = [];
  bool loading = true;
  bool failed = false;
  int request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CartItemOptions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.product.id != widget.item.product.id ||
        oldWidget.store != widget.store) {
      options = [];
      _load();
    }
  }

  Future<void> _load() async {
    final token = ++request;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final result = await widget.store.getProductOptions(
        widget.item.product.id,
      );
      if (mounted && token == request) setState(() => options = result);
    } catch (_) {
      if (mounted && token == request) setState(() => failed = true);
    } finally {
      if (mounted && token == request) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    if (loading || failed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LText(
            '${item.color} · ${item.size}',
            style: theme.textTheme.bodyMedium,
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else ...[
            const LText('상품 옵션을 불러오지 못했어요.'),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const LText('다시 시도'),
            ),
          ],
        ],
      );
    }
    if (options.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LText(
            '${item.color} · ${item.size}',
            style: theme.textTheme.bodyMedium,
          ),
          const LText('현재 판매 가능한 옵션이 없습니다.'),
          TextButton(onPressed: _load, child: const LText('새로고침')),
        ],
      );
    }
    final colors = options.map((option) => option.color).toSet().toList();
    final sizes =
        options
            .where((option) => option.color == item.color)
            .map((option) => option.size)
            .toSet()
            .toList()
          ..sort(
            (a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0),
          );
    ProductOption? match(String color, String size) => options
        .where(
          (option) =>
              option.color == color &&
              option.size == size &&
              option.isAvailable,
        )
        .firstOrNull;
    final current = match(item.color, item.size);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButton<String>(
          isExpanded: true,
          value: colors.contains(item.color) ? item.color : null,
          hint: LText('${item.color} (옵션 없음)'),
          items: colors.map((color) {
            final available = options.any(
              (option) => option.color == color && option.isAvailable,
            );
            return DropdownMenuItem(
              value: color,
              enabled: available,
              child: LText(
                available ? color : '$color (품절)',
                style: theme.textTheme.bodySmall,
              ),
            );
          }).toList(),
          onChanged: (color) {
            if (color == null) return;
            final candidates =
                options
                    .where(
                      (option) => option.color == color && option.isAvailable,
                    )
                    .toList()
                  ..sort(
                    (a, b) => (int.tryParse(a.size) ?? 0).compareTo(
                      int.tryParse(b.size) ?? 0,
                    ),
                  );
            final chosen = match(color, item.size) ?? candidates.firstOrNull;
            if (chosen != null) widget.onChanged(chosen);
          },
        ),
        DropdownButton<String>(
          isExpanded: true,
          value: sizes.contains(item.size) ? item.size : null,
          hint: LText('${item.size} (옵션 없음)'),
          items: sizes.map((size) {
            final available = match(item.color, size) != null;
            return DropdownMenuItem(
              value: size,
              enabled: available,
              child: LText(
                available ? size : '$size (품절)',
                style: theme.textTheme.bodySmall,
              ),
            );
          }).toList(),
          onChanged: sizes.isEmpty
              ? null
              : (size) {
                  if (size == null) return;
                  final chosen = match(item.color, size);
                  if (chosen != null) widget.onChanged(chosen);
                },
        ),
        if (current == null)
          LText(
            '저장된 옵션은 현재 주문할 수 없습니다. 옵션을 변경해주세요.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
      ],
    );
  }
}
