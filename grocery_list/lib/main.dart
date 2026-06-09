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

  @override
  void initState() {
    super.initState();
    _productsFuture = fetchProducts();
  }

  Future<List<Product>> fetchProducts() async {
    final url = Uri.parse('https://dummyjson.com/products/category/groceries');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final List productsJson = body['products'];
      return productsJson.map((json) => Product.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load products (${response.statusCode})');
    }
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
      body: FutureBuilder<List<Product>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (snapshot.hasData) {
            final products = snapshot.data!;
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
                      errorBuilder: (c, e, s) => const Icon(Icons.image),
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
    );
  }
}

class GroceryListScreen extends StatelessWidget {
  final List<Product> items;
  final void Function(Product) onRemove;

  const GroceryListScreen({
    super.key,
    required this.items,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Grocery List')),
      body: items.isEmpty
          ? const Center(child: Text('Your list is empty.'))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final product = items[index];
                return ListTile(
                  leading: Image.network(
                    product.thumbnail,
                    width: 50,
                    errorBuilder: (c, e, s) => const Icon(Icons.image),
                  ),
                  title: Text(product.title),
                  subtitle: Text('\$${product.price.toStringAsFixed(2)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: Colors.red,
                    onPressed: () => onRemove(product),
                  ),
                );
              },
            ),
    );
  }
}