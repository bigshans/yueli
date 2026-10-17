import 'package:flutter/material.dart';

/// 滑块 + 数字输入框联动：拖动改数值，输入框同步；输入也反过来更新滑块。
class SliderField extends StatelessWidget {
  const SliderField({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.controller,
    required this.onValue,
    this.format,
  });

  final int value;
  final int min;
  final int max;
  final String unit;
  final TextEditingController controller;
  final ValueChanged<int> onValue;
  final String Function(int)? format;

  @override
  Widget build(BuildContext context) {
    final sliderValue = value.toDouble().clamp(min.toDouble(), max.toDouble());
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: sliderValue,
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: format?.call(value) ?? '$value $unit',
            onChanged: (v) {
              final n = v.round();
              controller.text = '$n';
              onValue(n);
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 104,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              suffixText: unit,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) {
              final n = int.tryParse(v.trim());
              if (n != null && n > 0) onValue(n);
            },
          ),
        ),
      ],
    );
  }
}
