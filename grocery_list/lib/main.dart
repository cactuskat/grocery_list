import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: ProductListScreen());
  }
}

class Product {
  final int id;
  final String title;
  final String thumbnail;
  final double price;

  Product({
    required this.id,
    required this.title,
    required this.thumbnail,
    required this.price,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int,
      title: json['title'] as String,
      thumbnail: json['thumbnail'] as String,
      price: (json['price'] as num).toDouble(),
    );
  }
}

// A single gray placeholder row that mimics the real ListTile layout.
class SkeletonTile extends StatelessWidget {
  const SkeletonTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _box(50, 50), // stands in for the image
      title: _box(double.infinity, 14,
          margin: const EdgeInsets.only(right: 80)),
      subtitle: _box(60, 12, margin: const EdgeInsets.only(top: 6)),
      trailing: _box(28, 28), // stands in for the + button
    );
  }

  // Helper for a single rounded gray rectangle.
  Widget _box(double width, double height, {EdgeInsets? margin}) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

// Shows several skeleton rows stacked up.
class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 8});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: count,
      itemBuilder: (context, index) => const SkeletonTile(),
    );
  }
}

// A friendly full-screen error message with a retry button.
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

// A friendly full-screen message for when there's simply nothing to show.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const EmptyState({
    super.key,
    this.icon = Icons.inbox,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  late Future<List<Product>> _productsFuture;

  // The shared state: products the user has added to their list.
  // Using a Set keyed by product id makes "is this selected?" cheap.
  final Set<int> _selectedIds = {};
  final List<Product> _groceryList = [];

  // Tracks what we're currently showing, so refresh/retry can re-run it.
  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    _productsFuture = fetchProducts();
  }

  // DummyJSON has no search-within-category endpoint, 
  // so the move is: always fetch the groceries category, then filter that list by the query client-side
  Future<List<Product>> fetchProducts({String query = ''}) async {
  // Always pull the groceries category — DummyJSON can't search within one.
  final url = Uri.parse('https://dummyjson.com/products/category/groceries');

  final response = await http.get(url);

  if (response.statusCode == 200) {
    final body = jsonDecode(response.body);
    final List productsJson = body['products'];
    final products =
        productsJson.map((json) => Product.fromJson(json)).toList();

    // No query → return everything. Otherwise filter by title client-side.
    if (query.isEmpty) return products;

    final lowerQuery = query.toLowerCase();
    return products
        .where((p) => p.title.toLowerCase().contains(lowerQuery))
        .toList();
  } else {
    throw Exception('Failed to load products (${response.statusCode})');
  }
}

  // Re-run the current search and rebuild so the FutureBuilder watches it.
  void _retry() {
    setState(() {
      _productsFuture = fetchProducts(query: _currentQuery);
    });
  }

  // Run a new search from the search bar.
  void _search(String query) {
    setState(() {
      _currentQuery = query;
      _productsFuture = fetchProducts(query: query);
    });
  }

  void _addToList(Product product) {
    setState(() {
      _selectedIds.add(product.id);
      _groceryList.add(product);
    });
  }

  void _removeFromList(Product product) {
    setState(() {
      _selectedIds.remove(product.id);
      _groceryList.removeWhere((p) => p.id == product.id);
    });
  }

  void _openGroceryList() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => GroceryListScreen(
          items: _groceryList,
          onRemove: _removeFromList,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groceries'),
        actions: [
          // Cart button with a badge showing how many items are in the list.
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart),
                onPressed: _openGroceryList,
              ),
              if (_groceryList.isNotEmpty)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      '${_groceryList.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar — submitting runs a real API query.
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Search groceries...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          // The list fills the rest of the space, so it's wrapped in Expanded.
          Expanded(
            child: RefreshIndicator(
              // Pull-to-refresh re-runs the current search and waits for it.
              onRefresh: () async {
                setState(() {
                  _productsFuture = fetchProducts(query: _currentQuery);
                });
                await _productsFuture;
              },
              child: FutureBuilder<List<Product>>(
                future: _productsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SkeletonList();
                  } else if (snapshot.hasError) {
                    return ErrorState(
                      message:
                          'We couldn\'t load the groceries. Check your connection and try again.',
                      onRetry: _retry,
                    );
                  } else if (snapshot.hasData) {
                    final products = snapshot.data!;

                    // The request succeeded but came back with nothing to show.
                    if (products.isEmpty) {
                      return const EmptyState(
                        icon: Icons.search_off,
                        title: 'No groceries found',
                        message: 'Try a different search term.',
                      );
                    }

                    return ListView.builder(
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final product = products[index];
                        final isSelected = _selectedIds.contains(product.id);

                        return ListTile(
                          // Opacity dims the whole row when selected.
                          leading: Opacity(
                            opacity: isSelected ? 0.4 : 1.0,
                            child: Image.network(
                              product.thumbnail,
                              width: 50,
                              errorBuilder: (c, e, s) =>
                                  const Icon(Icons.image),
                            ),
                          ),
                          title: Opacity(
                            opacity: isSelected ? 0.4 : 1.0,
                            child: Text(product.title),
                          ),
                          subtitle: Opacity(
                            opacity: isSelected ? 0.4 : 1.0,
                            child: Text('\$${product.price.toStringAsFixed(2)}'),
                          ),
                          // Show a plus when not selected, a check when it is.
                          trailing: isSelected
                              ? const Icon(Icons.check, color: Colors.green)
                              : IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  color: Theme.of(context).primaryColor,
                                  onPressed: () => _addToList(product),
                                ),
                        );
                      },
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GroceryListScreen extends StatefulWidget {
  final List<Product> items;
  final void Function(Product) onRemove;

  const GroceryListScreen({
    super.key,
    required this.items,
    required this.onRemove,
  });

  @override
  State<GroceryListScreen> createState() => _GroceryListScreenState();
}

class _GroceryListScreenState extends State<GroceryListScreen> {
  // Tracks which items are checked off but not yet removed.
  final Set<int> _checkedIds = {};
  bool _loading = true; // start in the loading state

  @override
  void initState() {
    super.initState();
    // Briefly show the skeleton, then reveal the real list.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  void _toggle(Product product, bool? checked) {
    setState(() {
      if (checked == true) {
        _checkedIds.add(product.id);
      } else {
        _checkedIds.remove(product.id);
      }
    });
  }

  // Called when the screen is leaving. Commit the removals.
  void _commitRemovals() {
    // Snapshot the checked items first, then remove from the live list.
    final toRemove = widget.items
        .where((product) => _checkedIds.contains(product.id))
        .toList();

    for (final product in toRemove) {
      widget.onRemove(product);
    }
  }

  @override
  Widget build(BuildContext context) {
    // PopScope lets us run code right before the screen is popped.
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _commitRemovals();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Grocery List'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Done',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        body: _loading
            ? const SkeletonList()
            : widget.items.isEmpty
                ? const EmptyState(
                    icon: Icons.shopping_cart_outlined,
                    title: 'Your list is empty',
                    message:
                        'Add some groceries from the catalog to get started.',
                  )
                : ListView.builder(
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) {
                      final product = widget.items[index];
                      final isChecked = _checkedIds.contains(product.id);

                      return ListTile(
                        // Image on the left — matches the catalog and the skeleton's leading box.
                        leading: Image.network(
                          product.thumbnail,
                          width: 50,
                          errorBuilder: (c, e, s) => const Icon(Icons.image),
                        ),
                        title: Text(
                          product.title,
                          // Strike through checked items for visual feedback.
                          style: TextStyle(
                            decoration: isChecked
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                            color: isChecked ? Colors.grey : null,
                          ),
                        ),
                        subtitle: Text('\$${product.price.toStringAsFixed(2)}'),
                        // Checkbox on the right — within thumb reach, matches the skeleton's
                        // trailing box and the catalog's trailing + button.
                        trailing: Checkbox(
                          value: isChecked,
                          onChanged: (checked) => _toggle(product, checked),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}