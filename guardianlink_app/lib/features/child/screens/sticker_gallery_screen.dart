import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/auth_provider.dart';

class StickerGalleryScreen extends StatelessWidget {
  const StickerGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final stickers = user?.stickers ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Sticker Collection'),
        backgroundColor: Colors.purple,
      ),
      body: stickers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star_border, size: 100, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No stickers yet!',
                    style: TextStyle(fontSize: 24, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Complete tasks to earn stickers',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    color: Colors.purple[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.emoji_events, size: 40, color: Colors.purple),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Total Stickers',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '${stickers.length} collected',
                                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Your Collection',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: stickers.length,
                      itemBuilder: (context, index) {
                        return Card(
                          elevation: 4,
                          child: Center(
                            child: Text(
                              stickers[index].toString(),
                              style: const TextStyle(fontSize: 40),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
