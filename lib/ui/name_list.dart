import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Liste d'artistes ou de genres (nom + nombre de morceaux), même style que les lignes de morceaux.
class NameList extends StatelessWidget {
  const NameList({
    super.key,
    required this.names,
    required this.title,
    required this.onPick,
  });
  final Stream<List<(String, int)>> names;
  final String title;
  final void Function(String name) onPick;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(30, 26, 30, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: StreamBuilder<List<(String, int)>>(
            stream: names,
            builder: (_, snap) {
              final list = snap.data ?? const <(String, int)>[];
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onPick(list[i].$1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            list[i].$1,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Text(
                          '${list[i].$2}',
                          style: TextStyle(
                            color: context.colors.sub,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}
