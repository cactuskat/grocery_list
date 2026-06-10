import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:convert';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: ProductListScreen());
  }
}

// ---------------- PRODUCT MODEL ----------------

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

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: int.parse(map['apiId'].toString()),
      title: map['title'] as String,
      thumbnail: map['thumbnail'] as String,
      price: (map['price'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'apiId': id,
      'title': title,
      'thumbnail': thumbnail,
      'price': price,
    };
  }
}

// ---------------- DATABASE ----------------

class GroceryDatabase {
  static final GroceryDatabase instance = GroceryDatabase._init();
  static Database? _database;

  GroceryDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDB('grocery.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, fileName);

  return await openDatabase(
    path,
    version: 2,
    onCreate: _createDB,
    onUpgrade: _onUpgrade,
  );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE grocery_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        apiId INTEGER UNIQUE NOT NULL,
        title TEXT NOT NULL,
        thumbnail TEXT NOT NULL,
        price REAL NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await db.execute('DROP TABLE IF EXISTS grocery_items');

    await _createDB(db, newVersion);
  }

  Future<void> addItem(Product product) async {
    final db = await database;

    await db.insert(
      'grocery_items',
      product.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Product>> getItems() async {
    final db = await database;

    final result = await db.query('grocery_items');

    return result.map((map) => Product.fromMap(map)).toList();
  }

  Future<void> removeItem(int apiId) async {
    final db = await database;

    await db.delete(
      'grocery_items',
      where: 'apiId = ?',
      whereArgs: [apiId],
    );
  }
}

// ---------------- SELECTION PAGE ----------------

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  late Future<List<Product>> _productsFuture;
  List<Product> savedItems = [];
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _productsFuture = fetchProducts();
    loadSavedItems();
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

  Future<void> loadSavedItems() async {
    final items = await GroceryDatabase.instance.getItems();

    setState(() {
      savedItems = items;
    });
  }

  Future<void> addToList(Product product) async {
    await GroceryDatabase.instance.addItem(product);
    await loadSavedItems();
  }

  void openGroceryList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const GroceryListScreen(),
      ),
    );

    await loadSavedItems();
  }

  // Searching List
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void searchProducts() {
    setState(() {
      searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  void clearSearch() {
    setState(() {
      _searchController.clear();
      searchQuery = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedIds = savedItems.map((item) => item.id).toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groceries'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: openGroceryList,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search groceries',
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: clearSearch,
                      ),
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: searchProducts,
                    ),
                  ],
                ),
              ),
              onChanged: (value) {
                setState(() {});
              },
              onSubmitted: (value) {
                searchProducts();
              },
            ),
          ),

          Expanded(
            child: FutureBuilder<List<Product>>(
              future: _productsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (!snapshot.hasData) {
                  return const SizedBox.shrink();
                }

                final products = snapshot.data!;
                final selectedIds = savedItems.map((item) => item.id).toSet();

                final availableProducts = products.where((product) {
                  final isNotSaved = !selectedIds.contains(product.id);
                  final matchesSearch = product.title
                      .toLowerCase()
                      .contains(searchQuery);

                  return isNotSaved && matchesSearch;
                }).toList();

                if (products.isEmpty) {
                  return const Center(
                    child: Text('No grocery products were returned.'),
                  );
                }

                if (availableProducts.isEmpty && searchQuery.isNotEmpty) {
                  return const Center(
                    child: Text('No results match your search.'),
                  );
                }

                if (availableProducts.isEmpty) {
                  return const Center(
                    child: Text('No available groceries right now.'),
                  );
                }

                return ListView.builder(
                  itemCount: availableProducts.length,
                  itemBuilder: (context, index) {
                    final product = availableProducts[index];

                    return ListTile(
                      leading: Image.network(
                        product.thumbnail,
                        width: 50,
                        errorBuilder: (c, e, s) => const Icon(Icons.image),
                      ),
                      title: Text(product.title),
                      subtitle: Text('\$${product.price.toStringAsFixed(2)}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => addToList(product),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- GROCERY LIST PAGE ----------------

class GroceryListScreen extends StatefulWidget {
  const GroceryListScreen({super.key});

  @override
  State<GroceryListScreen> createState() => _GroceryListScreenState();
}

class _GroceryListScreenState extends State<GroceryListScreen> {
  List<Product> groceryItems = [];

  @override
  void initState() {
    super.initState();
    loadGroceryItems();
  }

  Future<void> loadGroceryItems() async {
    final items = await GroceryDatabase.instance.getItems();

    setState(() {
      groceryItems = items;
    });
  }

  Future<void> removeItem(Product product) async {
    await GroceryDatabase.instance.removeItem(product.id);
    await loadGroceryItems();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Grocery List'),
      ),
      body: groceryItems.isEmpty
          ? const Center(child: Text('Your list is empty.'))
          : ListView.builder(
              itemCount: groceryItems.length,
              itemBuilder: (context, index) {
                final product = groceryItems[index];

                return CheckboxListTile(
                  value: false,
                  title: Text(product.title),
                  subtitle: Text('\$${product.price.toStringAsFixed(2)}'),
                  secondary: Image.network(
                    product.thumbnail,
                    width: 50,
                    errorBuilder: (c, e, s) => const Icon(Icons.image),
                  ),
                  onChanged: (value) {
                    removeItem(product);
                  },
                );
              },
            ),
    );
  }
}