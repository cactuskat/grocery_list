import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}

enum SortOrder {
  alphabetical,
  price,
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

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
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

  Future<void> clearAllItems() async {
    final db = await database;
    await db.delete('grocery_items');
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;
  int refreshCount = 0;

  void switchTab(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  void refreshBothScreens() {
    setState(() {
      refreshCount++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      ProductListScreen(
        refreshCount: refreshCount,
        onDataChanged: refreshBothScreens,
        onGoToGroceryList: () => switchTab(1),
      ),
      GroceryListScreen(
        refreshCount: refreshCount,
        onDataChanged: refreshBothScreens,
        onGoToProducts: () => switchTab(0),
      ),
    ];

    return Scaffold(
      body: screens[selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: switchTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.store),
            label: 'Products',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart),
            label: 'My List',
          ),
        ],
      ),
    );
  }
}

class ProductListScreen extends StatefulWidget {
  final int refreshCount;
  final VoidCallback onDataChanged;
  final VoidCallback onGoToGroceryList;

  const ProductListScreen({
    super.key,
    required this.refreshCount,
    required this.onDataChanged,
    required this.onGoToGroceryList,
  });

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  late Future<List<Product>> _productsFuture;

  final TextEditingController _searchController = TextEditingController();

  List<Product> savedItems = [];
  String searchQuery = '';
  SortOrder currentSort = SortOrder.alphabetical;

  bool isOfflineMode = false;

  @override
  void initState() {
    super.initState();

    _productsFuture = fetchProducts();
    loadSavedItems();
    loadSortPreference();
  }

  @override
  void didUpdateWidget(covariant ProductListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.refreshCount != widget.refreshCount) {
      loadSavedItems();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Product>> fetchProducts() async {
    final url = Uri.parse('https://dummyjson.com/products/category/groceries');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            isOfflineMode = false;
          });
        }

        final body = jsonDecode(response.body);
        final List productsJson = body['products'];

        return productsJson.map((json) => Product.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load products.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isOfflineMode = true;
        });
      }

      rethrow;
    }
  }

  Future<void> loadSavedItems() async {
    final items = await GroceryDatabase.instance.getItems();

    if (!mounted) return;

    setState(() {
      savedItems = items;
    });
  }

  Future<void> loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSort = prefs.getString('sortOrder') ?? 'alphabetical';

    if (!mounted) return;

    setState(() {
      currentSort =
          savedSort == 'price' ? SortOrder.price : SortOrder.alphabetical;
    });
  }

  Future<void> saveSortPreference(SortOrder sortOrder) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('sortOrder', sortOrder.name);

    if (!mounted) return;

    setState(() {
      currentSort = sortOrder;
    });
  }

  Future<void> addToList(Product product) async {
    await GroceryDatabase.instance.addItem(product);
    await loadSavedItems();

    widget.onDataChanged();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.title} added to grocery list.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void retryFetchProducts() {
    setState(() {
      _productsFuture = fetchProducts();
    });
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
          PopupMenuButton<SortOrder>(
            icon: const Icon(Icons.sort),
            onSelected: saveSortPreference,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: SortOrder.alphabetical,
                child: Text('Alphabetical'),
              ),
              PopupMenuItem(
                value: SortOrder.price,
                child: Text('Lowest Price'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: widget.onGoToGroceryList,
          ),
        ],
      ),
      body: Column(
        children: [
          if (isOfflineMode) const OfflineStatusBar(),
          SearchBox(
            controller: _searchController,
            hintText: 'Search groceries',
            onSearch: searchProducts,
            onClear: clearSearch,
            onTyping: () {
              setState(() {});
            },
          ),
          Expanded(
            child: FutureBuilder<List<Product>>(
              future: _productsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const ProductSkeleton();
                }

                if (snapshot.hasError) {
                  return ErrorRetryMessage(
                    message:
                        'Could not load groceries. Please check your connection.',
                    onRetry: retryFetchProducts,
                  );
                }

                if (!snapshot.hasData) {
                  return const SizedBox.shrink();
                }

                final products = snapshot.data!;

                final availableProducts = products.where((product) {
                  final isNotSaved = !selectedIds.contains(product.id);
                  final matchesSearch =
                      product.title.toLowerCase().contains(searchQuery);

                  return isNotSaved && matchesSearch;
                }).toList();

                if (currentSort == SortOrder.alphabetical) {
                  availableProducts.sort(
                    (a, b) => a.title.compareTo(b.title),
                  );
                } else {
                  availableProducts.sort(
                    (a, b) => a.price.compareTo(b.price),
                  );
                }

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

                    return Dismissible(
                      key: ValueKey(product.id),
                      direction: DismissDirection.startToEnd,
                      background: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 24),
                        color: Colors.green,
                        child: const Icon(
                          Icons.shopping_cart,
                          color: Colors.white,
                        ),
                      ),
                      onDismissed: (direction) {
                        addToList(product);
                      },
                      child: ListTile(
                        leading: Image.network(
                          product.thumbnail,
                          width: 50,
                          errorBuilder: (c, e, s) =>
                              const Icon(Icons.image),
                        ),
                        title: Text(product.title),
                        subtitle:
                            Text('\$${product.price.toStringAsFixed(2)}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => addToList(product),
                        ),
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

class GroceryListScreen extends StatefulWidget {
  final int refreshCount;
  final VoidCallback onDataChanged;
  final VoidCallback onGoToProducts;

  const GroceryListScreen({
    super.key,
    required this.refreshCount,
    required this.onDataChanged,
    required this.onGoToProducts,
  });

  @override
  State<GroceryListScreen> createState() => _GroceryListScreenState();
}

class _GroceryListScreenState extends State<GroceryListScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<Product> groceryItems = [];
  String searchQuery = '';
  String? errorMessage;
  bool isLoading = true;

  SortOrder currentSort = SortOrder.alphabetical;

  @override
  void initState() {
    super.initState();

    loadGroceryItems();
    loadSortPreference();
  }

  @override
  void didUpdateWidget(covariant GroceryListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.refreshCount != widget.refreshCount) {
      loadGroceryItems();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> loadGroceryItems() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final items = await GroceryDatabase.instance.getItems();

      if (!mounted) return;

      setState(() {
        groceryItems = items;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        groceryItems = [];
        errorMessage = 'Could not load your grocery list.';
        isLoading = false;
      });
    }
  }

  Future<void> removeItem(Product product) async {
    await GroceryDatabase.instance.removeItem(product.id);
    await loadGroceryItems();

    widget.onDataChanged();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.title} moved back to groceries.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> clearAllItems() async {
    await GroceryDatabase.instance.clearAllItems();
    await loadGroceryItems();

    widget.onDataChanged();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Grocery list cleared.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();

    final savedSort =
        prefs.getString('grocerySortOrder') ??
        'alphabetical';

    if (!mounted) return;

    setState(() {
      currentSort = savedSort == 'price'
          ? SortOrder.price
          : SortOrder.alphabetical;
    });
  }

  Future<void> saveSortPreference(
    SortOrder sortOrder,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'grocerySortOrder',
      sortOrder.name,
    );

    if (!mounted) return;

    setState(() {
      currentSort = sortOrder;
    });
  }

  void searchGroceryList() {
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
    final filteredItems = groceryItems.where((product) {
      return product.title.toLowerCase().contains(searchQuery);
    }).toList();

    if (currentSort == SortOrder.alphabetical) {
      filteredItems.sort(
        (a, b) => a.title.compareTo(b.title),
      );
    } else {
      filteredItems.sort(
        (a, b) => a.price.compareTo(b.price),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Grocery List'),
        actions: [
          PopupMenuButton<SortOrder>(
            icon: const Icon(Icons.sort),
            onSelected: saveSortPreference,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: SortOrder.alphabetical,
                child: Text('Alphabetical'),
              ),
              PopupMenuItem(
                value: SortOrder.price,
                child: Text('Lowest Price'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear All',
            onPressed: groceryItems.isEmpty
                ? null
                : () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: const Text('Clear Grocery List'),
                          content: const Text(
                            'Remove all items from your grocery list?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                Navigator.pop(context);
                                await clearAllItems();
                              },
                              child: const Text('Clear All'),
                            ),
                          ],
                        );
                      },
                    );
                  },
          ),
        ],
      ),
      body: isLoading
          ? const GroceryListSkeleton()
          : errorMessage != null
              ? ErrorRetryMessage(
                  message: errorMessage!,
                  onRetry: loadGroceryItems,
                )
              : Column(
                  children: [
                    SearchBox(
                      controller: _searchController,
                      hintText: 'Search your grocery list',
                      onSearch: searchGroceryList,
                      onClear: clearSearch,
                      onTyping: () {
                        setState(() {});
                      },
                    ),
                    Expanded(
                      child: groceryItems.isEmpty
                          ? EmptyGroceryListMessage(
                              onGoToProducts: widget.onGoToProducts,
                            )
                          : filteredItems.isEmpty && searchQuery.isNotEmpty
                              ? const Center(
                                  child: Text('No items match your search.'),
                                )
                              : ListView.builder(
                                  itemCount: filteredItems.length,
                                  itemBuilder: (context, index) {
                                    final product = filteredItems[index];

                                    return Dismissible(
                                      key: ValueKey(product.id),
                                      direction: DismissDirection.endToStart,
                                      background: Container(
                                        alignment: Alignment.centerRight,
                                        padding:
                                            const EdgeInsets.only(right: 24),
                                        color: Colors.red,
                                        child: const Icon(
                                          Icons.undo,
                                          color: Colors.white,
                                        ),
                                      ),
                                      onDismissed: (direction) {
                                        removeItem(product);
                                      },
                                      child: CheckboxListTile(
                                        value: false,
                                        title: Text(product.title),
                                        subtitle: Text(
                                          '\$${product.price.toStringAsFixed(2)}',
                                        ),
                                        secondary: Image.network(
                                          product.thumbnail,
                                          width: 50,
                                          errorBuilder: (c, e, s) =>
                                              const Icon(Icons.image),
                                        ),
                                        onChanged: (value) {
                                          removeItem(product);
                                        },
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
    );
  }
}

class SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final VoidCallback onSearch;
  final VoidCallback onClear;
  final VoidCallback onTyping;

  const SearchBox({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onSearch,
    required this.onClear,
    required this.onTyping,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hintText,
          border: const OutlineInputBorder(),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (controller.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClear,
                ),
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: onSearch,
              ),
            ],
          ),
        ),
        onChanged: (value) {
          onTyping();
        },
        onSubmitted: (value) {
          onSearch();
        },
      ),
    );
  }
}

class EmptyGroceryListMessage extends StatelessWidget {
  final VoidCallback onGoToProducts;

  const EmptyGroceryListMessage({
    super.key,
    required this.onGoToProducts,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Welcome! Your grocery list is empty.\n\nGo to the products page and tap + to add your first item.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onGoToProducts,
              icon: const Icon(Icons.store),
              label: const Text('Browse Products'),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductSkeleton extends StatelessWidget {
  const ProductSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 8,
      itemBuilder: (context, index) {
        return const ListTile(
          leading: CircleAvatar(
            radius: 25,
            backgroundColor: Colors.black12,
          ),
          title: SizedBox(
            height: 16,
            child: ColoredBox(
              color: Colors.black12,
            ),
          ),
          subtitle: Padding(
            padding: EdgeInsets.only(top: 8),
            child: SizedBox(
              height: 12,
              child: ColoredBox(
                color: Colors.black12,
              ),
            ),
          ),
        );
      },
    );
  }
}

class GroceryListSkeleton extends StatelessWidget {
  const GroceryListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 6,
      itemBuilder: (context, index) {
        return const CheckboxListTile(
          value: false,
          onChanged: null,
          title: SizedBox(
            height: 16,
            child: ColoredBox(
              color: Colors.black12,
            ),
          ),
          secondary: CircleAvatar(
            radius: 25,
            backgroundColor: Colors.black12,
          ),
        );
      },
    );
  }
}

class ErrorRetryMessage extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorRetryMessage({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class OfflineStatusBar extends StatelessWidget {
  const OfflineStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.orange,
      padding: const EdgeInsets.all(8),
      child: const Text(
        'Offline mode: showing saved grocery list only.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white),
      ),
    );
  }
}