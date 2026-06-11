# Grocery List

## Fieldstone Grocers List
Grocery managment app that allows users to browse products from a store called 'Fieldstone Grocers' and use them in a shopping list.

## API Used
api link: https://dummyjson.com/
"DummyJSON can be used with any type of front end project that needs products, carts, users, todos or any dummy data in JSON format.
You can use examples below to check how DummyJSON works."

Full Product List/ Example Endpoint URL:
```dart
    https://dummyjson.com/products/category/groceries
```

## Demo Video
https://www.loom.com/share/b1ca50bdb65d499894561b9a359d9db3

## Storage Strategy
SQLite: stores the local persistent data and the actual grocery list items. Allows saved items to be viewed offline without calling the API again. Used as provides structured data and offline viewing. Stored fields: apiId, title, thumbnail, and price

Shared_Preferences: small app settings. Remember whether displaying list should be sorted alphabetically or by lowest price. Is used to sort because it is a simple key/value setting, rather than a full data record. Too weak to be used as a full database. Stored values: sortOrder, grocerySortOrder

## Data Format
Each saved item is in a row withh columns: id, apiId, title, thumbnail, price. SQLite (via sqflite) is used to store the strctured data. The database is used to store which products are the ones added to the list. If the table is empty, it is assumed there are no items in the grocery list.

## How to Run
1. open on VSCode -> terminal
2. flutter clean
3. flutter pub get
4. flutter run
5. 1 (for Windows)

## How to Test Persistence:
1. Add item(s) to grocery list
2. Kill App/Close Window
3. Reopen using "How to Run" steps
4. Verify items are still on list

## Edge Cases
Edge Case 1: No Internet Connection
The user launches the app without internet access.
Expected Behavior:
- API request fails.
- Offline banner appears.
- User-friendly error message is displayed.
- Retry button is available.
- Previously saved grocery items remain accessible from SQLite.

Edge Case 2: Search Returns No Matches
The user searches for item when no grocery product contains those words. Ex. 'dragonfruit', 'pizza' , 'soap'
Expected Behavior:
- App does not crash.
- Empty results message appears: "No results match your search."
- Clear button restores the full list.

Edge Case 3: First App Launch (Empty Database)
The user installs the app for the first time and has never added any groceries.
Expected Behavior:
- Grocery list screen opens successfully.
- SQLite returns an empty list.
- Welcome message is shown.
- No crashes or null errors occur.