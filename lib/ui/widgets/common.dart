import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';

/// A bordered surface used everywhere instead of Material's elevated Card —
/// flat panels render faster and read better at high information density.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.color,
    this.borderColor,
    this.radius = 10,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = color ??
        (theme.brightness == Brightness.dark
            ? const Color(0xFF1B2027)
            : Colors.white);
    final body = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? AppTheme.borderOf(context)),
      ),
      child: child,
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: body,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.icon});

  final String text;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
          ],
          Text(
            text,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Headline number tile used on the dashboard and day-close screens.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.icon,
    this.tint,
    this.onTap,
  });

  final String label;
  final String value;
  final String? sub;
  final IconData? icon;
  final Color? tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? Theme.of(context).colorScheme.primary;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(width: 11),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (sub != null)
                  Text(
                    sub!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small coloured status pill (PAID / UNPAID / LOW STOCK …).
class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.color, this.icon});

  final String text;
  final Color? color;
  final IconData? icon;

  static Color colorFor(String status) {
    switch (status.toUpperCase()) {
      case 'PAID':
        return AppTheme.success;
      case 'PARTIAL':
        return AppTheme.warning;
      case 'UNPAID':
        return AppTheme.danger;
      case 'CANCELLED':
        return Colors.grey;
      default:
        return AppTheme.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? colorFor(text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: c),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message = '',
    this.icon = Icons.inbox_rounded,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: muted.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: muted)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Right-aligned money text with tabular figures so columns line up.
class Money extends StatelessWidget {
  const Money(
    this.value, {
    super.key,
    this.size = 13,
    this.bold = false,
    this.color,
    this.symbol = true,
    this.signed = false,
  });

  final num value;
  final double size;
  final bool bold;
  final Color? color;
  final bool symbol;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final text = symbol ? Fmt.money(value) : Fmt.amount(value);
    return Text(
      signed && value > 0 ? '+$text' : text,
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: size,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Compact labelled text field used across every form.
class Field extends StatelessWidget {
  const Field({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.prefix,
    this.suffix,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
    this.width,
    this.obscure = false,
    this.textAlign = TextAlign.start,
    this.helper,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final Widget? prefix;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool enabled;
  final bool autofocus;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final double? width;
  final bool obscure;
  final TextAlign textAlign;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscure,
      maxLines: obscure ? 1 : maxLines,
      textAlign: textAlign,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      textCapitalization: textCapitalization,
      style: const TextStyle(fontSize: 13.5),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        prefixIcon: prefix,
        suffixIcon: suffix,
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }

  /// Digits and one decimal point only.
  static List<TextInputFormatter> get decimal => [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
      ];
  static List<TextInputFormatter> get integer => [
        FilteringTextInputFormatter.digitsOnly,
      ];
  static List<TextInputFormatter> upper(int? max) => [
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
        if (max != null) LengthLimitingTextInputFormatter(max),
        TextInputFormatter.withFunction(
          (_, n) => n.copyWith(text: n.text.toUpperCase()),
        ),
      ];
}

/// Compact dropdown matching [Field]'s look.
class Picker<T> extends StatelessWidget {
  const Picker({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width,
    this.enabled = true,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final double? width;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final field = DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: enabled ? onChanged : null,
      isExpanded: true,
      style: TextStyle(
          fontSize: 13.5, color: Theme.of(context).colorScheme.onSurface),
      decoration: InputDecoration(labelText: label),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}

/// Keyboard-shortcut hint chip, e.g. `F9`.
class KeyHint extends StatelessWidget {
  const KeyHint(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.subtleOf(context),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.borderOf(context)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Date range selector shared by every report screen.
class DateRangeBar extends StatelessWidget {
  const DateRangeBar({
    super.key,
    required this.from,
    required this.to,
    required this.onChanged,
    this.trailing,
  });

  final DateTime from;
  final DateTime to;
  final void Function(DateTime from, DateTime to) onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final presets = <String, (DateTime, DateTime)>{
      'Today': (now, now),
      'Yesterday': (
        now.subtract(const Duration(days: 1)),
        now.subtract(const Duration(days: 1))
      ),
      'This week': (now.subtract(Duration(days: now.weekday - 1)), now),
      'This month': (DateTime(now.year, now.month, 1), now),
      'Last month': (
        DateTime(now.year, now.month - 1, 1),
        DateTime(now.year, now.month, 0)
      ),
      'This quarter': (
        DateTime(now.year, ((now.month - 1) ~/ 3) * 3 + 1, 1),
        now
      ),
      'This FY': (
        DateTime(now.month >= 4 ? now.year : now.year - 1, 4, 1),
        now
      ),
    };

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _dateButton(
            context, 'From', from, (d) => onChanged(d, d.isAfter(to) ? d : to)),
        _dateButton(context, 'To', to,
            (d) => onChanged(d.isBefore(from) ? d : from, d)),
        PopupMenuButton<String>(
          tooltip: 'Quick ranges',
          onSelected: (k) {
            final r = presets[k]!;
            onChanged(r.$1, r.$2);
          },
          itemBuilder: (_) => presets.keys
              .map((k) => PopupMenuItem(value: k, child: Text(k)))
              .toList(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.borderOf(context)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_repeat_rounded, size: 16),
                SizedBox(width: 6),
                Text('Quick range', style: TextStyle(fontSize: 13)),
                Icon(Icons.arrow_drop_down_rounded, size: 18),
              ],
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }

  Widget _dateButton(BuildContext context, String label, DateTime value,
      ValueChanged<DateTime> onPick) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today_rounded, size: 15),
      label: Text('$label: ${Fmt.date(value)}',
          style: const TextStyle(fontSize: 13)),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2015),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) onPick(picked);
      },
    );
  }
}

/// Toast helpers.
void toast(BuildContext context, String message,
    {bool error = false, bool success = false, Duration? duration}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error
                  ? Icons.error_outline_rounded
                  : success
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
              size: 18,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: error
            ? AppTheme.danger
            : success
                ? AppTheme.success
                : const Color(0xFF2B3038),
        duration: duration ?? Duration(seconds: error ? 5 : 3),
        width: 460,
      ),
    );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 17)),
      content: SizedBox(
        width: 420,
        child: Text(message, style: const TextStyle(fontSize: 13.5)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        ElevatedButton(
          style: destructive
              ? ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger,
                  foregroundColor: Colors.white)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Wraps a scrollable table so wide reports scroll horizontally instead of
/// overflowing the window.
class ScrollableTable extends StatefulWidget {
  const ScrollableTable({super.key, required this.child, this.minWidth = 900});

  final Widget child;
  final double minWidth;

  @override
  State<ScrollableTable> createState() => _ScrollableTableState();
}

class _ScrollableTableState extends State<ScrollableTable> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => Scrollbar(
        controller: _controller,
        thumbVisibility: box.maxWidth < widget.minWidth,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: box.maxWidth < widget.minWidth
                  ? widget.minWidth
                  : box.maxWidth,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class BusyOverlay extends StatelessWidget {
  const BusyOverlay({super.key, required this.busy, required this.child});

  final bool busy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (busy)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.25),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

/// Standard header row for the app's dialogs.
class DialogHeader extends StatelessWidget {
  const DialogHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
      child: Row(
        children: [
          Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16.5, fontWeight: FontWeight.w700)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
              ],
            ),
          ),
          ...actions,
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

/// Small uppercase caption that groups fields inside a form.
class FormSubheader extends StatelessWidget {
  const FormSubheader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

/// Lays out form fields in an evenly spaced row.
class FieldRow extends StatelessWidget {
  const FieldRow(this.children, {super.key, this.bottom = 12});

  final List<Widget> children;
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              Expanded(child: children[i]),
              if (i != children.length - 1) const SizedBox(width: 12),
            ],
          ],
        ),
      );
}

/// A text field with a dropdown of previously used values. Unlike
/// [Autocomplete] it never rewrites the controller during a rebuild, so the
/// caret stays where the operator put it.
class SuggestField extends StatefulWidget {
  const SuggestField({
    super.key,
    required this.label,
    required this.controller,
    required this.options,
    this.hint,
    this.capitalizeWords = false,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final List<String> options;
  final String? hint;
  final bool capitalizeWords;
  final ValueChanged<String>? onChanged;

  @override
  State<SuggestField> createState() => _SuggestFieldState();
}

class _SuggestFieldState extends State<SuggestField> {
  @override
  Widget build(BuildContext context) {
    return Field(
      label: widget.label,
      controller: widget.controller,
      hint: widget.hint,
      onChanged: widget.onChanged,
      textCapitalization: widget.capitalizeWords
          ? TextCapitalization.words
          : TextCapitalization.none,
      suffix: widget.options.isEmpty
          ? null
          : PopupMenuButton<String>(
              tooltip: 'Pick from existing',
              icon: const Icon(Icons.arrow_drop_down_rounded, size: 22),
              onSelected: (v) {
                widget.controller.text = v;
                widget.onChanged?.call(v);
                setState(() {});
              },
              itemBuilder: (_) => widget.options
                  .take(60)
                  .map((o) => PopupMenuItem(
                        value: o,
                        height: 36,
                        child: Text(o, style: const TextStyle(fontSize: 13)),
                      ))
                  .toList(),
            ),
    );
  }
}

/// Gives its child a definite width of at least [minWidth] and scrolls
/// horizontally when the window is narrower than that.
///
/// Wrap fixed-column lists in this: on a 1366 x 768 counter screen a table
/// that needs 950 px scrolls instead of throwing a RenderFlex overflow.
class MinWidthScroller extends StatefulWidget {
  const MinWidthScroller({
    super.key,
    required this.minWidth,
    required this.child,
  });

  final double minWidth;
  final Widget child;

  @override
  State<MinWidthScroller> createState() => _MinWidthScrollerState();
}

class _MinWidthScrollerState extends State<MinWidthScroller> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final tight = box.maxWidth < widget.minWidth;
        final content = SizedBox(
          width: tight ? widget.minWidth : box.maxWidth,
          child: widget.child,
        );
        if (!tight) return content;
        return Scrollbar(
          controller: _controller,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: content,
          ),
        );
      },
    );
  }
}

/// A page toolbar that flows onto extra lines instead of overflowing.
///
/// [leading] sits at the start and [actions] at the end while there is room;
/// on a narrow window the two groups stack. Every list screen uses this so
/// the app stays usable at the enforced 1100 x 680 minimum.
class Toolbar extends StatelessWidget {
  const Toolbar({
    super.key,
    this.leading = const [],
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 10),
  });

  final List<Widget> leading;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: leading,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ],
      ),
    );
  }
}

/// The tinted summary bar above a list. Wraps rather than overflowing.
class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      color: AppTheme.subtleOf(context),
      child: Wrap(
        spacing: 24,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}

/// A `label: value` pair for [StatStrip].
class StatText extends StatelessWidget {
  const StatText(this.label, this.value, {super.key, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
