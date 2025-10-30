import 'dart:io';

import 'package:flutter/material.dart';
import 'package:integrate_python_demo/pages/python_page.dart';

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    final type = Platform.isAndroid ? '内置' : '系统';
    final List<_Entry> entries = [
      _Entry(
        title: 'Python Demo',
        subtitle: '使用Rust ffi，调用${type}Python解释器执行脚本。使用异步操作读取Python解释器输出结果。',
        builder: () => PythonPage(title: '${type}Python解释器演示'),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Demo列表'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            double maxWidth = constraints.maxWidth;
            if (!maxWidth.isFinite || maxWidth <= 0) {
              maxWidth = MediaQuery.of(context).size.width;
            }

            double itemWidth;
            if (maxWidth > 720) {
              itemWidth = 320;
            } else if (maxWidth > 480) {
              itemWidth = (maxWidth - 48) / 2;
            } else {
              itemWidth = maxWidth - 32;
            }

            if (!itemWidth.isFinite || itemWidth <= 0) {
              itemWidth = maxWidth > 0 ? maxWidth : 0;
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: entries.map((entry) {
                    return SizedBox(
                      width: itemWidth,
                      child: _EntryCard(entry: entry),
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => entry.builder()));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(entry.title, style: Theme.of(context).textTheme.titleMedium),
              if (entry.subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  entry.subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: const [Icon(Icons.chevron_right)],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Entry {
  const _Entry({required this.title, this.subtitle, required this.builder});

  final String title;
  final String? subtitle;
  final Widget Function() builder;
}
