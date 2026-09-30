import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import 'common.dart';

Future<bool> deletePost(BuildContext context, Api api, Post post) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this content?'),
      content: const Text('It will be removed from your content list.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (yes != true) return false;
  try {
    await api.deletePost(post.id);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, e.message);
    return false;
  }
}
