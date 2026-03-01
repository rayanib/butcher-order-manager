import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = OrdersStore();
  await store.init(); // ✅ wait until SharedPreferences loads

  runApp(ButcherApp(store: store));
}

/* ===========================
   APP
=========================== */

class ButcherApp extends StatelessWidget {
  final OrdersStore store;
  const ButcherApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6D58A8),
        fontFamilyFallback: const ['Segoe UI', 'Arial'],
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: Shell(store: store), // ✅ pass store
    );
  }
}

/* ===========================
   SHELL (6 TABS)
   - Added Prices tab
=========================== */

class Shell extends StatefulWidget {
  final OrdersStore store;
  const Shell({super.key, required this.store});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;

  OrdersStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    // ❌ احذف store.init(); لأننا عملناها في main()
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      OrdersScreen(store: store),
      NewOrderScreen(store: store),
      FutureOrdersScreen(store: store),
      LiahScreen(store: store),
      PricesScreen(store: store),
      HistoryScreen(store: store),
    ];

    final title = switch (index) {
      0 => "الطلبات",
      1 => "طلب جديد",
      2 => "الطلبيات المستقبلية",
      3 => "طلبات اللِيّة",
      4 => "الأسعار",
      _ => "السجل",
    };

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            if (index == 0 && store.canUndoDone)
              IconButton(
                tooltip: "رجوع آخر خطوة",
                icon: const Icon(Icons.undo),
                onPressed: () async {
                  final ok = await store.undoLastDone();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok ? "تم الرجوع" : "لا يوجد خطوة للرجوع"),
                    ),
                  );
                },
              ),
          ],
        ),
        body: SafeArea(child: pages[index]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (v) => setState(() => index = v),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.receipt_long),
              label: "الطلبات",
            ),
            NavigationDestination(
              icon: Icon(Icons.add_circle_outline),
              label: "جديد",
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month),
              label: "مستقبل",
            ),
            NavigationDestination(
              icon: Icon(Icons.star_outline),
              label: "لِيّة",
            ),
            NavigationDestination(
              icon: Icon(Icons.price_change_outlined),
              label: "الأسعار",
            ),
            NavigationDestination(icon: Icon(Icons.history), label: "السجل"),
          ],
        ),
      ),
    );
  }
}

/* ===========================
   MODELS
=========================== */

enum ServiceType { pickup, delivery }

enum ItemValueType { kg, amount, none }

class Order {
  String customer;
  String phone;

  DateTime? pickupAt; // today countdown / fixed today time
  DateTime? scheduledFor; // future

  bool done;
  ServiceType service;

  List<OrderItem> items;

  // Money
  int totalShekel;
  int paidShekel;

  Order({
    required this.customer,
    required this.phone,
    this.pickupAt,
    this.scheduledFor,
    required this.items,
    this.done = false,
    this.service = ServiceType.pickup,
    this.totalShekel = 0,
    this.paidShekel = 0,
  });

  int get remainingShekel => (totalShekel - paidShekel).clamp(0, 1 << 30);
  bool get isPaid => remainingShekel == 0;
  String get debtText => isPaid ? "دفع" : "لم يدفع";

  Map<String, dynamic> toJson() => {
    "customer": customer,
    "phone": phone,
    "pickupAt": pickupAt?.toIso8601String(),
    "scheduledFor": scheduledFor?.toIso8601String(),
    "done": done,
    "service": service.name,
    "items": items.map((e) => e.toJson()).toList(),
    "totalShekel": totalShekel,
    "paidShekel": paidShekel,
  };

  static Order fromJson(Map<String, dynamic> j) => Order(
    customer: (j["customer"] ?? "").toString(),
    phone: (j["phone"] ?? "").toString(),
    pickupAt: j["pickupAt"] == null
        ? null
        : DateTime.tryParse(j["pickupAt"].toString()),
    scheduledFor: j["scheduledFor"] == null
        ? null
        : DateTime.tryParse(j["scheduledFor"].toString()),
    done: (j["done"] ?? false) == true,
    service: (j["service"] ?? "pickup").toString() == "delivery"
        ? ServiceType.delivery
        : ServiceType.pickup,
    items: ((j["items"] as List? ?? []))
        .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    totalShekel: (j["totalShekel"] is num)
        ? (j["totalShekel"] as num).toInt()
        : 0,
    paidShekel: (j["paidShekel"] is num) ? (j["paidShekel"] as num).toInt() : 0,
  );
}

class OrderItem {
  String name;

  ItemValueType valueType;
  double? kg;
  int? amount;

  List<String> extras;
  String? status;
  String? note;

  OrderItem({
    required this.name,
    this.valueType = ItemValueType.kg,
    this.kg,
    this.amount,
    this.extras = const [],
    this.status,
    this.note,
  });

  OrderItem copy() => OrderItem(
    name: name,
    valueType: valueType,
    kg: kg,
    amount: amount,
    extras: List.of(extras),
    status: status,
    note: note,
  );

  String get titleLine {
    final parts = <String>[name];
    if (extras.isNotEmpty) parts.add(extras.join("، "));
    if (status != null && status!.trim().isNotEmpty) parts.add(status!);
    if (note != null && note!.trim().isNotEmpty) parts.add(note!);
    return parts.join(" - ");
  }

  String get valueText {
    switch (valueType) {
      case ItemValueType.amount:
        return amount == null ? "₪ -" : "₪ $amount";
      case ItemValueType.kg:
        return kg == null ? "- كغم" : "${kg!.toStringAsFixed(1)} كغم";
      case ItemValueType.none:
        return "بدون كمية";
    }
  }

  void setValueType(ItemValueType t) {
    valueType = t;
    if (t == ItemValueType.kg) {
      kg ??= 1.0;
      amount = null;
    } else if (t == ItemValueType.amount) {
      amount ??= 0;
      kg = null;
    } else {
      kg = null;
      amount = null;
    }
  }

  Map<String, dynamic> toJson() => {
    "name": name,
    "valueType": valueType.name,
    "kg": kg,
    "amount": amount,
    "extras": extras,
    "status": status,
    "note": note,
  };

  static OrderItem fromJson(Map<String, dynamic> j) => OrderItem(
    name: (j["name"] ?? "").toString(),
    valueType: (() {
      final s = (j["valueType"] ?? "kg").toString();
      if (s == "amount") return ItemValueType.amount;
      if (s == "none") return ItemValueType.none;
      return ItemValueType.kg;
    })(),
    kg: (j["kg"] is num) ? (j["kg"] as num).toDouble() : null,
    amount: (j["amount"] is num) ? (j["amount"] as num).toInt() : null,
    extras: ((j["extras"] as List?) ?? []).map((e) => e.toString()).toList(),
    status: j["status"]?.toString(),
    note: j["note"]?.toString(),
  );
}

class LiahOrder {
  final String name;
  final String phone;
  final String qty;

  LiahOrder({required this.name, required this.phone, required this.qty});

  Map<String, dynamic> toJson() => {"name": name, "phone": phone, "qty": qty};

  static LiahOrder fromJson(Map<String, dynamic> j) => LiahOrder(
    name: (j["name"] ?? "").toString(),
    phone: (j["phone"] ?? "").toString(),
    qty: (j["qty"] ?? "-").toString(),
  );
}

class HistoryEntry {
  final Order order;
  final DateTime finishedAt;

  // ✅ manual paid flag (History only)
  bool paidManual;

  HistoryEntry({
    required this.order,
    required this.finishedAt,
    this.paidManual = true, // default: paid
  });

  Map<String, dynamic> toJson() => {
    "order": order.toJson(),
    "finishedAt": finishedAt.toIso8601String(),
    "paidManual": paidManual,
  };

  static HistoryEntry fromJson(Map<String, dynamic> j) => HistoryEntry(
    order: Order.fromJson(j["order"] as Map<String, dynamic>),
    finishedAt:
        DateTime.tryParse((j["finishedAt"] ?? "").toString()) ?? DateTime.now(),
    paidManual: (j["paidManual"] ?? true) == true, // old entries default paid
  );
}

/* ===========================
   PRICES (MEAT ONLY)
=========================== */

class MeatPricesStore extends ChangeNotifier {
  SharedPreferences? _prefs;
  static const _kKey = "meat_prices_v1";

  // ₪ per KG
  final Map<String, int> prices = {};

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    final raw = _prefs!.getString(_kKey);
    prices.clear();
    if (raw != null && raw.trim().isNotEmpty) {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in j.entries) {
        final v = e.value;
        if (v is num) prices[e.key] = v.toInt();
      }
    }
    notifyListeners();
  }

  int getPrice(String itemName) => prices[itemName] ?? 0;

  Future<void> setPrice(String itemName, int shekelPerKg) async {
    prices[itemName] = shekelPerKg;
    await _prefs!.setString(_kKey, jsonEncode(prices));
    notifyListeners();
  }
}

/* ===========================
   STORE + PERSIST
=========================== */

class OrdersStore extends ChangeNotifier {
  final List<Order> orders = [];
  final List<LiahOrder> liahOrders = [];
  final List<HistoryEntry> history = [];

  final Set<String> customerNames = {};
  SharedPreferences? _prefs;

  final MeatPricesStore meatPrices = MeatPricesStore();

  static const _kNamesKey = "customer_names_v5";
  static const _kOrdersKey = "orders_v5";
  static const _kLiahKey = "liah_v5";
  static const _kHistoryKey = "history_v5";

  // history auto-delete (days)
  static const int historyKeepDays = 4;

  // Undo stack (only last done)
  HistoryEntry? _lastDoneEntry;
  Order? _lastDoneOrderSnapshot;
  Future<void> setHistoryPaid(HistoryEntry e, bool paid) async {
    e.paidManual = paid;
    await _saveHistory();
    notifyListeners();
  }

  bool get canUndoDone =>
      _lastDoneEntry != null && _lastDoneOrderSnapshot != null;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await meatPrices.init(_prefs!);

    // names
    final names = _prefs!.getStringList(_kNamesKey) ?? [];
    customerNames
      ..clear()
      ..addAll(names);

    // orders
    final ordersStr = _prefs!.getString(_kOrdersKey);
    orders.clear();
    if (ordersStr != null && ordersStr.trim().isNotEmpty) {
      final list = jsonDecode(ordersStr) as List;
      orders.addAll(list.map((e) => Order.fromJson(e as Map<String, dynamic>)));
    }

    // liah
    final liahStr = _prefs!.getString(_kLiahKey);
    liahOrders.clear();
    if (liahStr != null && liahStr.trim().isNotEmpty) {
      final list = jsonDecode(liahStr) as List;
      liahOrders.addAll(
        list.map((e) => LiahOrder.fromJson(e as Map<String, dynamic>)),
      );
    }

    // history
    final histStr = _prefs!.getString(_kHistoryKey);
    history.clear();
    if (histStr != null && histStr.trim().isNotEmpty) {
      final list = jsonDecode(histStr) as List;
      history.addAll(
        list.map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>)),
      );
    }

    _cleanupHistory();

    // recalc totals (in case prices changed)
    _recalcAllTotals();

    await _saveAll();
    notifyListeners();
  }

  void _cleanupHistory() {
    final cutoff = DateTime.now().subtract(
      const Duration(days: historyKeepDays),
    );
    history.removeWhere((h) => h.finishedAt.isBefore(cutoff));
  }

  Future<void> _saveAll() async {
    await _saveNames();
    await _saveOrders();
    await _saveLiah();
    await _saveHistory();
  }

  Future<void> _saveNames() async {
    if (_prefs == null) return;
    final list = customerNames.toList()..sort();
    await _prefs!.setStringList(_kNamesKey, list);
  }

  Future<void> _saveOrders() async {
    if (_prefs == null) return;
    final list = orders.map((e) => e.toJson()).toList();
    await _prefs!.setString(_kOrdersKey, jsonEncode(list));
  }

  Future<void> _saveLiah() async {
    if (_prefs == null) return;
    final list = liahOrders.map((e) => e.toJson()).toList();
    await _prefs!.setString(_kLiahKey, jsonEncode(list));
  }

  Future<void> _saveHistory() async {
    if (_prefs == null) return;
    final list = history.map((e) => e.toJson()).toList();
    await _prefs!.setString(_kHistoryKey, jsonEncode(list));
  }

  void rememberCustomer(String name) {
    final n = name.trim();
    if (n.isEmpty) return;
    if (!customerNames.contains(n)) {
      customerNames.add(n);
      _saveNames();
      notifyListeners();
    }
  }

  int calcOrderTotal(List<OrderItem> items) {
    int total = 0;
    for (final it in items) {
      if (it.valueType == ItemValueType.amount) {
        total += (it.amount ?? 0);
      } else if (it.valueType == ItemValueType.kg) {
        final kg = it.kg ?? 0.0;
        final p = meatPrices.getPrice(it.name); // meat only
        total += (kg * p).round();
      }
    }
    return total;
  }

  void _recalcAllTotals() {
    for (final o in orders) {
      o.totalShekel = calcOrderTotal(o.items);
      if (o.paidShekel > o.totalShekel) o.paidShekel = o.totalShekel;
    }
    for (final h in history) {
      h.order.totalShekel = calcOrderTotal(h.order.items);
      if (h.order.paidShekel > h.order.totalShekel)
        h.order.paidShekel = h.order.totalShekel;
    }
  }

  Future<void> addOrder(Order o) async {
    rememberCustomer(o.customer);
    o.totalShekel = calcOrderTotal(o.items);
    if (o.paidShekel > o.totalShekel) o.paidShekel = o.totalShekel;

    orders.insert(0, o);
    await _saveOrders();
    notifyListeners();
  }

  Future<void> removeOrder(Order o) async {
    // حذف قوي بدل remove() (يحذف حتى لو كان في مشكلة ref)
    orders.removeWhere((x) {
      final sameCustomer = x.customer.trim() == o.customer.trim();
      final samePhone = x.phone.trim() == o.phone.trim();

      final samePickup =
          (x.pickupAt?.toIso8601String() ?? "") ==
          (o.pickupAt?.toIso8601String() ?? "");

      final sameScheduled =
          (x.scheduledFor?.toIso8601String() ?? "") ==
          (o.scheduledFor?.toIso8601String() ?? "");

      final sameItemsCount = x.items.length == o.items.length;

      return sameCustomer &&
          samePhone &&
          samePickup &&
          sameScheduled &&
          sameItemsCount;
    });

    await _saveOrders(); // ✅ مهم جدًا
    notifyListeners();
  }

  Future<void> updateOrder() async {
    _recalcAllTotals();
    await _saveOrders();
    await _saveHistory();
    notifyListeners();
  }

  Future<void> markDone(Order o) async {
  // snapshot for undo (copy)
  _lastDoneOrderSnapshot = Order(
    customer: o.customer,
    phone: o.phone,
    pickupAt: o.pickupAt,
    scheduledFor: o.scheduledFor,
    items: o.items.map((e) => e.copy()).toList(),
    done: false,
    service: o.service,
    totalShekel: o.totalShekel,
    paidShekel: o.paidShekel,
  );

  // ✅ remove from active orders so orders_v5 doesn't grow forever
  orders.remove(o);

  // ✅ add COPY to history (not the same object)
  final histOrder = Order(
    customer: _lastDoneOrderSnapshot!.customer,
    phone: _lastDoneOrderSnapshot!.phone,
    pickupAt: _lastDoneOrderSnapshot!.pickupAt,
    scheduledFor: _lastDoneOrderSnapshot!.scheduledFor,
    items: _lastDoneOrderSnapshot!.items.map((e) => e.copy()).toList(),
    done: true,
    service: _lastDoneOrderSnapshot!.service,
    totalShekel: _lastDoneOrderSnapshot!.totalShekel,
    paidShekel: _lastDoneOrderSnapshot!.paidShekel,
  );

  final entry = HistoryEntry(order: histOrder, finishedAt: DateTime.now());
  history.insert(0, entry);
  _lastDoneEntry = entry;

  await _saveHistory();
  await _saveOrders();
  notifyListeners();
}

Future<bool> undoLastDone() async {
  if (!canUndoDone) return false;

  // remove the history entry we just added
  history.remove(_lastDoneEntry);

  final snap = _lastDoneOrderSnapshot!;

  // restore back to active orders
  final restored = Order(
    customer: snap.customer,
    phone: snap.phone,
    pickupAt: snap.pickupAt,
    scheduledFor: snap.scheduledFor,
    items: snap.items.map((e) => e.copy()).toList(),
    done: false,
    service: snap.service,
    totalShekel: snap.totalShekel,
    paidShekel: snap.paidShekel,
  );

  orders.insert(0, restored);

  _lastDoneEntry = null;
  _lastDoneOrderSnapshot = null;

  await _saveHistory();
  await _saveOrders();
  notifyListeners();
  return true;
}
  // LIAH
  Future<void> addLiah(LiahOrder o) async {
    rememberCustomer(o.name);
    liahOrders.insert(0, o);
    await _saveLiah();
    notifyListeners();
  }

  Future<void> removeLiah(LiahOrder o) async {
    liahOrders.remove(o);
    await _saveLiah();
    notifyListeners();
  }

  Future<void> updateLiah(int index, LiahOrder newOrder) async {
    if (index < 0 || index >= liahOrders.length) return;
    liahOrders[index] = newOrder;
    rememberCustomer(newOrder.name);
    await _saveLiah();
    notifyListeners();
  }

  // HISTORY actions
  Future<void> clearHistory() async {
    history.clear();
    await _saveHistory();
    notifyListeners();
  }

  Future<void> deleteCustomerEverywhere(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;

    // delete from active orders
    orders.removeWhere((o) => o.customer.trim() == n);

    // delete from future orders too (same list but keep it safe)
    // (future orders are also in orders list, so this is enough)

    // delete from liah
    liahOrders.removeWhere((o) => o.name.trim() == n);

    // delete from history
    history.removeWhere((h) => h.order.customer.trim() == n);

    await _saveAll();
    notifyListeners();
  }

  Future<void> deleteHistoryEntry(HistoryEntry e) async {
    history.remove(e);
    await _saveHistory();
    notifyListeners();
  }
}

/* ===========================
   HELPERS
=========================== */

String two(int x) => x.toString().padLeft(2, '0');

String formatDateTimeShort(DateTime d) {
  return "${two(d.day)}/${two(d.month)}  ${two(d.hour)}:${two(d.minute)}";
}

bool isOverdue(DateTime? target) {
  if (target == null) return false;
  return DateTime.now().isAfter(target);
}

String countdownLabel(DateTime target) {
  final diff = target.difference(DateTime.now());
  if (diff.isNegative) {
    final a = diff.abs();
    final h = a.inHours;
    final m = a.inMinutes % 60;
    final s = a.inSeconds % 60;
    return "متأخر: ${two(h)}:${two(m)}:${two(s)}";
  } else {
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    return "متبقي: ${two(h)}:${two(m)}:${two(s)}";
  }
}

DateTime todayAt(TimeOfDay t) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, t.hour, t.minute);
}

/* ===========================
   PRODUCTS (CATEGORIES)
   - Added كباب, برغر under "لحمة ناعمة..."
   - Added سلق مع عظم(عجل), رقبه عجل
=========================== */

const Map<String, List<String>> productGroups = {
  "شاورما وطلبات سريعة": ["شاورما"],
  "لحمة ناعمة / كبة / كفته": [
    "ناعم",
    "ناعم بدون دهن",
    "خشن",
    "كبه",
    "صفايح كفته",
    "كباب",
    "برغر",
  ],
  "حوسي": ["حوسي", "حوسي للحمص"],
  "سلق": [
    "موزات سلق",
    "سلق عادي",
    "سلق مع عظم(عجل)",
    "رقبه عجل",
    "غنم سلق مع عظم",
    "غنم سلق بدون عظم",
  ],
  "غنم": ["غنم", "غنم كبه", "ريش غنم"],
  "شوي": ["سينتا شوي", "شوي كعب فخذ", "فيليه"],
  "أخرى": ["مشروبات", "شيبس", "خبز", "سلطة"],
};

Set<String> meatItemsForPricing() {
  // Meat only (exclude "أخرى")
  final meat = <String>{};
  for (final e in productGroups.entries) {
    if (e.key == "أخرى") continue;
    for (final name in e.value) {
      // price only for kg items normally; still allow setting price for anything here
      meat.add(name);
    }
  }
  return meat;
}

/* ===========================
   COMPACT UI COMPONENTS
=========================== */

class CompactValuePill extends StatelessWidget {
  final String text;
  const CompactValuePill({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 98),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.10),
        border: Border.all(color: cs.primary.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class MoneyPill extends StatelessWidget {
  final String text;
  const MoneyPill({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

class OrderItemRowCompact extends StatelessWidget {
  final OrderItem it;
  const OrderItemRowCompact({super.key, required this.it});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CompactValuePill(text: it.valueText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "• ${it.titleLine}",
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

/* ===========================
   ORDERS SCREEN (GRID on tablet)
   - removed QuickRepeat card
   - overdue orders appear first
=========================== */

/* ===========================
   ORDERS SCREEN (GRID on tablet)
   - overdue orders appear first
   - SnackBar fixed (no stuck)
=========================== */

class OrdersScreen extends StatefulWidget {
  final OrdersStore store;
  const OrdersScreen({Key? key, required this.store}) : super(key: key);

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });

    widget.store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  Future<void> _doneWithSnack(Order o) async {
    await widget.store.markDone(o);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("تم حفظ الطلب")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orders = widget.store.orders
    .where((o) => !o.done && o.scheduledFor == null)
    .toList();
    if (orders.isEmpty) {
      return const Center(child: Text("لا يوجد طلبات"));
    }

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;

        // ✅ أكثر بطاقات بالشاشة: عدد أعمدة حسب عرض الجهاز
        int cross = (w / 420).floor();
        if (cross < 2) cross = 2;
        if (cross > 4) cross = 4;

        // ✅ ارتفاع مريح للكرت (بدون overflow)
        final ratio = w >= 700 ? 2.75 : 2.35;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 130),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: ratio,
          ),
          itemCount: orders.length,
          itemBuilder: (_, i) {
            final o = orders[i];
            return OrderCardCompact(
              order: o,
              onDone: () => _doneWithSnack(o),
              onEdit: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => EditOrderSheet(order: o, store: widget.store),
                );
              },
              onCancel: () => widget.store.removeOrder(o),
            );
          },
        );
      },
    );
  }
}

class MiniPill extends StatelessWidget {
  final String text;
  const MiniPill({Key? key, required this.text}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // ✅ يقلل تأثير تكبير الخط تبع الجهاز
    final mq = MediaQuery.of(context);
    final safe = mq.copyWith(textScaler: const TextScaler.linear(1.0));

    return MediaQuery(
      data: safe,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(999),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(text, style: const TextStyle(fontSize: 11)),
        ),
      ),
    );
  }
}

class TimePillCompact extends StatelessWidget {
  final Order order;
  const TimePillCompact({Key? key, required this.order}) : super(key: key);

  String _hhmm(DateTime d) =>
      "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";

  @override
  Widget build(BuildContext context) {
    final dt = order.scheduledFor ?? order.pickupAt;
    if (dt == null) return const MiniPill(text: "—");

    // ✅ المطلوب: عرض وقت الانتهاء مباشرة (مثال 12:00)
    final finish = _hhmm(dt);

    // لو صار الوقت وخلص، خلّيها واضحة
    final overdue = DateTime.now().isAfter(dt);
    return MiniPill(text: overdue ? "متأخر • $finish" : "ينتهي • $finish");
  }
}

class OrderCardCompact extends StatelessWidget {
  final Order order;
  final VoidCallback onDone;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  const OrderCardCompact({
    Key? key,
    required this.order,
    required this.onDone,
    required this.onEdit,
    required this.onCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final total = order.totalShekel;

    // Prevent Xiaomi / browser font scaling overflow
    final mq = MediaQuery.of(context);
    final safe = mq.copyWith(textScaler: const TextScaler.linear(1.0));

    return MediaQuery(
      data: safe,
      child: Card(
        elevation: 1.2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              /// ---------- CUSTOMER + TIME ----------
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.customer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TimePillCompact(order: order),
                ],
              ),

              const SizedBox(height: 4),

              /// ---------- PHONE + SERVICE ----------
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.phone.trim().isEmpty ? "—" : order.phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  MiniPill(text: _serviceLabel(order.service)),
                ],
              ),

              const SizedBox(height: 6),

              /// ---------- TOTAL ----------
              Row(
                children: [
                  Expanded(child: MiniPill(text: "المجموع ₪ $total")),
                ],
              ),

              const SizedBox(height: 6),

              /// ---------- ITEMS ----------
              Text(
                _itemsPreview(order),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),

              const SizedBox(height: 6),

              /// ---------- BUTTONS ----------
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: OutlinedButton.icon(
                        onPressed: onDone,
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text(
                          "تم",
                          style: TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: OutlinedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text(
                          "تعديل",
                          style: TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: onCancel,
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: "حذف",
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ---------- ITEMS PREVIEW ----------
  String _itemsPreview(Order o) {
    if (o.items.isEmpty) return "—";
    final parts = o.items.take(2).map((e) => e.titleLine).toList();
    final more = o.items.length > 2 ? " +${o.items.length - 2}" : "";
    return parts.join(" • ") + more;
  }

  /// ---------- SERVICE LABEL ----------
  String _serviceLabel(dynamic service) {
    final s = (service ?? "").toString().toLowerCase();
    if (s.contains("pickup") || s.contains("استلام")) return "استلام";
    if (s.contains("delivery") || s.contains("توصيل")) return "توصيل";
    if (s.contains("local") || s.contains("محلي")) return "محلي";
    if (s.contains("takeaway") || s.contains("سفري")) return "استلام";
    return s.isEmpty ? "—" : service.toString();
  }
}
class _Pill extends StatelessWidget {
  final String text;
  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}


class _ItemChip extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;

  const _ItemChip({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (value.isNotEmpty) ...[
                  Text(value),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/* ===========================
   FUTURE ORDERS SCREEN
=========================== */

class FutureOrdersScreen extends StatefulWidget {
  final OrdersStore store;
  const FutureOrdersScreen({super.key, required this.store});

  @override
  State<FutureOrdersScreen> createState() => _FutureOrdersScreenState();
}

class _FutureOrdersScreenState extends State<FutureOrdersScreen> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final future =
        widget.store.orders
            .where((o) => !o.done && o.scheduledFor != null)
            .toList()
          ..sort((a, b) => a.scheduledFor!.compareTo(b.scheduledFor!));

    if (future.isEmpty) {
      return const Center(
        child: Text(
          "لا توجد طلبيات مستقبلية",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ...future.map(
          (o) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
           child: OrderCardCompact(
              order: o,
              onDone: () async {
                  await widget.store.markDone(o);
                },
              onEdit: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => EditOrderSheet(order: o, store: widget.store),
                );
              },
              onCancel: () => widget.store.removeOrder(o),
            ),
          ),
        ),
      ],
    );
  }
}

/* ===========================
   DIALOGS (Cuts, Shawarma, Kofta, Kabab, Burger, Manual)
=========================== */

class CutDialog extends StatefulWidget {
  final String baseName;
  const CutDialog({super.key, required this.baseName});

  @override
  State<CutDialog> createState() => _CutDialogState();
}

class _CutDialogState extends State<CutDialog> {
  String cut = "ستيك";
  double kg = 1.0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.baseName,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: "ستيك", label: Text("ستيك")),
              ButtonSegment(value: "شرحات", label: Text("شرحات")),
              ButtonSegment(value: "شيش", label: Text("شيش")),
            ],
            selected: {cut},
            onSelectionChanged: (s) => setState(() => cut = s.first),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {
                  if (kg > 0.5) setState(() => kg -= 0.5);
                },
                icon: const Icon(Icons.remove),
              ),
              Text(
                "${kg.toStringAsFixed(1)} كغم",
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              IconButton(
                onPressed: () => setState(() => kg += 0.5),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("إلغاء"),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              OrderItem(
                name: widget.baseName,
                valueType: ItemValueType.kg,
                kg: kg,
                note: cut,
              ),
            );
          },
          child: const Text(
            "إضافة",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class ShawarmaDialog extends StatefulWidget {
  const ShawarmaDialog({super.key});

  @override
  State<ShawarmaDialog> createState() => _ShawarmaDialogState();
}

class _ShawarmaDialogState extends State<ShawarmaDialog> {
  double kg = 1.0;
  String status = "جاهز";
  bool spiceOnSide = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        "شاورما",
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {
                  if (kg > 0.5) setState(() => kg -= 0.5);
                },
                icon: const Icon(Icons.remove),
              ),
              Text(
                "${kg.toStringAsFixed(1)} كغم",
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              IconButton(
                onPressed: () => setState(() => kg += 0.5),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: "جاهز", label: Text("جاهز")),
              ButtonSegment(value: "مش جاهز", label: Text("مش جاهز")),
            ],
            selected: {status},
            onSelectionChanged: (s) => setState(() => status = s.first),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            value: spiceOnSide,
            onChanged: (v) => setState(() => spiceOnSide = v),
            title: const Text(
              "بهار عجنب",
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("إلغاء"),
        ),
        FilledButton(
          onPressed: () {
            final extras = <String>[];
            if (spiceOnSide) extras.add("بهار عجنب");
            Navigator.pop(
              context,
              OrderItem(
                name: "شاورما",
                valueType: ItemValueType.kg,
                kg: kg,
                status: status,
                extras: extras,
              ),
            );
          },
          child: const Text(
            "إضافة",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class KoftaDialog extends StatefulWidget {
  const KoftaDialog({super.key});

  @override
  State<KoftaDialog> createState() => _KoftaDialogState();
}

class _KoftaDialogState extends State<KoftaDialog> {
  double kg = 1.0;
  String status = "جاهز";
  final Set<String> extras = {};
  final List<String> options = const ["بصل", "بقدونس", "بندوره", "ثوم", "حد"];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        "صفايح كفته",
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () {
                    if (kg > 0.5) setState(() => kg -= 0.5);
                  },
                  icon: const Icon(Icons.remove),
                ),
                Text(
                  "${kg.toStringAsFixed(1)} كغم",
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                IconButton(
                  onPressed: () => setState(() => kg += 0.5),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((o) {
                return FilterChip(
                  label: Text(
                    o,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  selected: extras.contains(o),
                  onSelected: (v) {
                    setState(() {
                      if (v)
                        extras.add(o);
                      else
                        extras.remove(o);
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: "جاهز", label: Text("جاهز")),
                ButtonSegment(value: "مش جاهز", label: Text("مش جاهز")),
              ],
              selected: {status},
              onSelectionChanged: (s) => setState(() => status = s.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("إلغاء"),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              OrderItem(
                name: "صفايح كفته",
                valueType: ItemValueType.kg,
                kg: kg,
                extras: extras.toList(),
                status: status,
              ),
            );
          },
          child: const Text(
            "إضافة",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class KababDialog extends StatefulWidget {
  const KababDialog({super.key});

  @override
  State<KababDialog> createState() => _KababDialogState();
}

class _KababDialogState extends State<KababDialog> {
  double kg = 1.0;
  String spice = "حد";
  String status = "جاهز";

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("كباب", style: TextStyle(fontWeight: FontWeight.w900)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {
                  if (kg > 0.5) setState(() => kg -= 0.5);
                },
                icon: const Icon(Icons.remove),
              ),
              Text(
                "${kg.toStringAsFixed(1)} كغم",
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              IconButton(
                onPressed: () => setState(() => kg += 0.5),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: "حد", label: Text("حد")),
              ButtonSegment(value: "حلو", label: Text("حلو")),
            ],
            selected: {spice},
            onSelectionChanged: (s) => setState(() => spice = s.first),
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: "جاهز", label: Text("جاهز")),
              ButtonSegment(value: "مش جاهز", label: Text("مش جاهز")),
            ],
            selected: {status},
            onSelectionChanged: (s) => setState(() => status = s.first),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("إلغاء"),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              OrderItem(
                name: "كباب",
                valueType: ItemValueType.kg,
                kg: kg,
                extras: [spice],
                status: status,
              ),
            );
          },
          child: const Text(
            "إضافة",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class BurgerDialog extends StatefulWidget {
  const BurgerDialog({super.key});

  @override
  State<BurgerDialog> createState() => _BurgerDialogState();
}

class _BurgerDialogState extends State<BurgerDialog> {
  double kg = 1.0;
  String status = "جاهز";

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("برغر", style: TextStyle(fontWeight: FontWeight.w900)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {
                  if (kg > 0.5) setState(() => kg -= 0.5);
                },
                icon: const Icon(Icons.remove),
              ),
              Text(
                "${kg.toStringAsFixed(1)} كغم",
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              IconButton(
                onPressed: () => setState(() => kg += 0.5),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: "جاهز", label: Text("جاهز")),
              ButtonSegment(value: "فقط لحم", label: Text("فقط لحم")),
            ],
            selected: {status},
            onSelectionChanged: (s) => setState(() => status = s.first),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("إلغاء"),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              OrderItem(
                name: "برغر",
                valueType: ItemValueType.kg,
                kg: kg,
                status: status,
              ),
            );
          },
          child: const Text(
            "إضافة",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class ManualItemDialog extends StatefulWidget {
  const ManualItemDialog({super.key});

  @override
  State<ManualItemDialog> createState() => _ManualItemDialogState();
}

class _ManualItemDialogState extends State<ManualItemDialog> {
  final nameCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  ItemValueType type = ItemValueType.none;
  double kg = 1.0;
  final amountCtrl = TextEditingController();

  @override
  void dispose() {
    nameCtrl.dispose();
    noteCtrl.dispose();
    amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        "إضافة صنف يدوي",
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "اسم الصنف"),
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 10),
            SegmentedButton<ItemValueType>(
              segments: const [
                ButtonSegment(value: ItemValueType.none, label: Text("بدون")),
                ButtonSegment(value: ItemValueType.kg, label: Text("وزن")),
                ButtonSegment(value: ItemValueType.amount, label: Text("سعر")),
              ],
              selected: {type},
              onSelectionChanged: (s) => setState(() => type = s.first),
            ),
            const SizedBox(height: 12),
            if (type == ItemValueType.kg)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () {
                      if (kg > 0.5) setState(() => kg -= 0.5);
                    },
                    icon: const Icon(Icons.remove),
                  ),
                  Text(
                    "${kg.toStringAsFixed(1)} كغم",
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  IconButton(
                    onPressed: () => setState(() => kg += 0.5),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            if (type == ItemValueType.amount)
              TextField(
                controller: amountCtrl,
                decoration: const InputDecoration(labelText: "₪ السعر"),
                keyboardType: TextInputType.number,
              ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: "ملاحظة (اختياري)"),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("إلغاء"),
        ),
        FilledButton(
          onPressed: () {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) return;

            final note = noteCtrl.text.trim().isEmpty
                ? null
                : noteCtrl.text.trim();

            if (type == ItemValueType.amount) {
              final val = int.tryParse(amountCtrl.text.trim());
              if (val == null) return;
              Navigator.pop(
                context,
                OrderItem(
                  name: name,
                  valueType: ItemValueType.amount,
                  amount: val,
                  note: note,
                ),
              );
              return;
            }
            if (type == ItemValueType.kg) {
              Navigator.pop(
                context,
                OrderItem(
                  name: name,
                  valueType: ItemValueType.kg,
                  kg: kg,
                  note: note,
                ),
              );
              return;
            }
            Navigator.pop(
              context,
              OrderItem(name: name, valueType: ItemValueType.none, note: note),
            );
          },
          child: const Text(
            "إضافة",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

/* ===========================
   TIME PICKERS
=========================== */

class _TodayTimeChips extends StatelessWidget {
  final void Function(Duration) onPick;
  final void Function(DateTime) onPickDateTime;
  final DateTime? selected;

  const _TodayTimeChips({
    required this.onPick,
    required this.onPickDateTime,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final options = <Duration>[
      const Duration(minutes: 5),
      const Duration(minutes: 10),
      const Duration(minutes: 15),
      const Duration(minutes: 30),
      const Duration(hours: 1),
      const Duration(hours: 2),
      const Duration(hours: 3),
      const Duration(hours: 4),
      const Duration(hours: 5),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ...options.map((d) {
          final label = d.inHours >= 1
              ? "${d.inHours} ساعة"
              : "${d.inMinutes} دقيقة";
          return FilledButton.tonal(
            onPressed: () => onPick(d),
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          );
        }),
        OutlinedButton.icon(
          icon: const Icon(Icons.access_time),
          label: const Text(
            "وقت محدد اليوم...",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          onPressed: () async {
            final t = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.now(),
            );
            if (t == null) return;
            final dt = todayAt(t);
            
            onPickDateTime(dt);
          },
        ),
        if (selected != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              "المحدد: ${formatDateTimeShort(selected!)}",
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
      ],
    );
  }
}

class _FuturePicker extends StatelessWidget {
  final DateTime? value;
  final void Function(DateTime) onPick;

  const _FuturePicker({required this.value, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.event),
      label: Text(
        value == null ? "اختيار التاريخ والوقت" : formatDateTimeShort(value!),
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      onPressed: () async {
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          firstDate: now,
          lastDate: now.add(const Duration(days: 60)),
          initialDate: now,
        );
        if (d == null) return;

        final t = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.now(),
        );
        if (t == null) return;

        onPick(DateTime(d.year, d.month, d.day, t.hour, t.minute));
      },
    );
  }
}

/* ===========================
   ITEM EDIT CARD
=========================== */

class ItemEditorCard extends StatelessWidget {
  final OrderItem it;
  final VoidCallback onDelete;
  final void Function(ItemValueType) onType;
  final VoidCallback onKgMinus;
  final VoidCallback onKgPlus;
  final void Function(String) onAmountChanged;
  final TextEditingController noteCtrl;

  const ItemEditorCard({
    super.key,
    required this.it,
    required this.onDelete,
    required this.onType,
    required this.onKgMinus,
    required this.onKgPlus,
    required this.onAmountChanged,
    required this.noteCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  it.titleLine,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: "حذف",
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<ItemValueType>(
            segments: const [
              ButtonSegment(value: ItemValueType.none, label: Text("بدون")),
              ButtonSegment(value: ItemValueType.kg, label: Text("وزن")),
              ButtonSegment(value: ItemValueType.amount, label: Text("سعر")),
            ],
            selected: {it.valueType},
            onSelectionChanged: (s) => onType(s.first),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              CompactValuePill(text: it.valueText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  it.valueType == ItemValueType.none
                      ? "هذا الصنف بدون كمية/سعر"
                      : it.valueType == ItemValueType.kg
                      ? "تعديل الوزن"
                      : "تعديل السعر",
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (it.valueType == ItemValueType.kg)
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: onKgMinus,
                  icon: const Icon(Icons.remove),
                  label: const Text("0.5-"),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: onKgPlus,
                  icon: const Icon(Icons.add),
                  label: const Text("0.5+"),
                ),
              ],
            ),
          if (it.valueType == ItemValueType.amount)
            TextField(
              decoration: const InputDecoration(labelText: "₪ السعر"),
              keyboardType: TextInputType.number,
              onChanged: onAmountChanged,
            ),
          const SizedBox(height: 10),
          TextField(
            controller: noteCtrl,
            decoration: const InputDecoration(labelText: "ملاحظة (اختياري)"),
          ),
        ],
      ),
    );
  }
}

/* ===========================
   EDIT ORDER SHEET
   - Add payment fields (دفع/لم يدفع + مبلغ مدفوع)
   - Use better keyboard settings for name
=========================== */

class EditOrderSheet extends StatefulWidget {
  final Order order;
  final OrdersStore store;
  const EditOrderSheet({super.key, required this.order, required this.store});

  @override
  State<EditOrderSheet> createState() => _EditOrderSheetState();
}

class _EditOrderSheetState extends State<EditOrderSheet> {
  late TextEditingController nameCtrl;
  late TextEditingController phoneCtrl;
  late TextEditingController paidCtrl;

  late bool isFuture;
  DateTime? scheduledFor;
  DateTime? pickupAt;

  late List<OrderItem> items;
  late ServiceType service;

  final Map<int, TextEditingController> noteCtrls = {};

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.order.customer);
    phoneCtrl = TextEditingController(text: widget.order.phone);
    paidCtrl = TextEditingController(text: widget.order.paidShekel.toString());

    isFuture = widget.order.scheduledFor != null;
    scheduledFor = widget.order.scheduledFor;
    pickupAt = widget.order.pickupAt;

    service = widget.order.service;
    items = widget.order.items.map((e) => e.copy()).toList();

    for (int i = 0; i < items.length; i++) {
      noteCtrls[i] = TextEditingController(text: items[i].note ?? "");
    }
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    paidCtrl.dispose();
    for (final c in noteCtrls.values) c.dispose();
    super.dispose();
  }

  bool _needsCutDialog(String name) {
    const cutTargets = {
      "غنم",
      "غنم كبه",
      "ريش غنم",
      "سينتا شوي",
      "شوي كعب فخذ",
      "فيليه",
    };
    return cutTargets.contains(name);
  }

  Future<void> _addFromButton(String name) async {
    if (name == "صفايح كفته") {
      final res = await showDialog<OrderItem>(
        context: context,
        builder: (_) => const KoftaDialog(),
      );
      if (res != null) setState(() => items.add(res));
      return;
    }
    if (name == "شاورما") {
      final res = await showDialog<OrderItem>(
        context: context,
        builder: (_) => const ShawarmaDialog(),
      );
      if (res != null) setState(() => items.add(res));
      return;
    }
    if (name == "كباب") {
      final res = await showDialog<OrderItem>(
        context: context,
        builder: (_) => const KababDialog(),
      );
      if (res != null) setState(() => items.add(res));
      return;
    }
    if (name == "برغر") {
      final res = await showDialog<OrderItem>(
        context: context,
        builder: (_) => const BurgerDialog(),
      );
      if (res != null) setState(() => items.add(res));
      return;
    }
    if (_needsCutDialog(name)) {
      final res = await showDialog<OrderItem>(
        context: context,
        builder: (_) => CutDialog(baseName: name),
      );
      if (res != null) setState(() => items.add(res));
      return;
    }

    setState(
      () => items.add(
        OrderItem(name: name, valueType: ItemValueType.kg, kg: 1.0),
      ),
    );
  }

  Future<void> _addManual() async {
    final res = await showDialog<OrderItem>(
      context: context,
      builder: (_) => const ManualItemDialog(),
    );
    if (res != null) setState(() => items.add(res));
  }

  Future<void> _saveAll() async {
    final customer = nameCtrl.text.trim();
    if (customer.isEmpty || items.isEmpty) return;

    for (int i = 0; i < items.length; i++) {
      items[i].note = noteCtrls[i]?.text.trim();
    }

    final paid = int.tryParse(paidCtrl.text.trim()) ?? 0;

    widget.order.customer = customer;
    widget.order.phone = phoneCtrl.text.trim();
    widget.order.pickupAt = isFuture ? null : pickupAt;
    widget.order.scheduledFor = isFuture ? scheduledFor : null;
    widget.order.service = service;
    widget.order.items = items.map((e) => e.copy()).toList();
    widget.order.totalShekel = widget.store.calcOrderTotal(widget.order.items);
    widget.order.paidShekel = paid.clamp(0, widget.order.totalShekel);

    widget.store.rememberCustomer(customer);
    await widget.store.updateOrder();
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final total = widget.store.calcOrderTotal(items);

    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        bottom: bottom + 14,
        top: 10,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text(
            "تعديل الطلب",
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Autocomplete<String>(
                    optionsBuilder: (v) {
                      final q = v.text.trim().toLowerCase();
                      if (q.isEmpty) return const Iterable<String>.empty();
                      return widget.store.customerNames
                          .where((n) => n.toLowerCase().startsWith(q))
                          .take(8);
                    },
                    onSelected: (s) {
                      nameCtrl.text = s;
                      widget.store.rememberCustomer(s);
                    },
                    fieldViewBuilder: (context, c, f, _) {
                      c.text = nameCtrl.text;
                      c.selection = TextSelection.fromPosition(
                        TextPosition(offset: c.text.length),
                      );
                      return TextField(
                        controller: c,
                        focusNode: f,
                        decoration: const InputDecoration(
                          labelText: "اسم الزبون",
                        ),
                        keyboardType: TextInputType.name,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        enableSuggestions: false,
                        onChanged: (v) {
                          nameCtrl.text = v;
                          widget.store.rememberCustomer(v);
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(labelText: "هاتف"),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      "طريقة الطلب",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<ServiceType>(
                    segments: const [
                      ButtonSegment(
                        value: ServiceType.pickup,
                        label: Text("استلام"),
                      ),
                      ButtonSegment(
                        value: ServiceType.delivery,
                        label: Text("توصيل"),
                      ),
                    ],
                    selected: {service},
                    onSelectionChanged: (s) =>
                        setState(() => service = s.first),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "وقت الاستلام",
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text("اليوم")),
                      ButtonSegment(value: true, label: Text("مستقبلي")),
                    ],
                    selected: {isFuture},
                    onSelectionChanged: (s) {
                      setState(() {
                        isFuture = s.first;
                        pickupAt = null;
                        scheduledFor = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (!isFuture)
                    _TodayTimeChips(
                      onPick: (dur) =>
                          setState(() => pickupAt = DateTime.now().add(dur)),
                      onPickDateTime: (dt) => setState(() => pickupAt = dt),
                      selected: pickupAt,
                    ),
                  if (isFuture)
                    _FuturePicker(
                      value: scheduledFor,
                      onPick: (dt) => setState(() => scheduledFor = dt),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "الدفع",
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      MoneyPill(text: "المجموع ₪ $total"),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: paidCtrl,
                          decoration: const InputDecoration(
                            labelText: "₪ المدفوع",
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "الحالة: ${(int.tryParse(paidCtrl.text.trim()) ?? 0) >= total ? "دفع" : "لم يدفع"}",
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "إضافة أصناف",
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _addManual,
                      icon: const Icon(Icons.edit_note),
                      label: const Text(
                        "إضافة صنف يدوي",
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...productGroups.entries.map((g) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            g.key,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: g.value.map((p) {
                              return SizedBox(
                                height: 46,
                                child: FilledButton(
                                  onPressed: () => _addFromButton(p),
                                  child: Text(
                                    p,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          if (items.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "تفاصيل الطلب",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    ...items.asMap().entries.map((e) {
                      final idx = e.key;
                      final it = e.value;
                      noteCtrls[idx] ??= TextEditingController(
                        text: it.note ?? "",
                      );

                      return ItemEditorCard(
                        it: it,
                        noteCtrl: noteCtrls[idx]!,
                        onDelete: () => setState(() => items.removeAt(idx)),
                        onType: (t) => setState(() => it.setValueType(t)),
                        onKgMinus: () => setState(() {
                          final current = it.kg ?? 1.0;
                          if (current > 0.5) it.kg = current - 0.5;
                        }),
                        onKgPlus: () => setState(() {
                          final current = it.kg ?? 1.0;
                          it.kg = current + 0.5;
                        }),
                        onAmountChanged: (v) => setState(() {
                          final val = int.tryParse(v.trim());
                          if (val == null) return;
                          it.amount = val;
                          it.valueType = ItemValueType.amount;
                        }),
                      );
                    }),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 12),

          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: _saveAll,
              icon: const Icon(Icons.save),
              label: const Text(
                "حفظ التعديل",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ===========================
   NEW ORDER SCREEN (Tablet POS)
   - Add payment fields + total visible
   - Better keyboard suggestions off
   - Kabab/Burger dialogs
=========================== */

class NewOrderScreen extends StatefulWidget {
  final OrdersStore store;
  const NewOrderScreen({super.key, required this.store});

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();

  bool isFuture = false;
  DateTime? scheduledFor;
  DateTime? pickupAt;

  ServiceType service = ServiceType.pickup;

  final List<OrderItem> items = [];
  final Map<int, TextEditingController> noteCtrls = {};

  late final List<String> _cats;
  String _selectedCat = "";

  @override
  void initState() {
    super.initState();
    _cats = productGroups.keys.toList();
    _selectedCat = _cats.isNotEmpty ? _cats.first : "";
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    for (final c in noteCtrls.values) c.dispose();
    super.dispose();
  }

  bool _needsCutDialog(String name) {
    const cutTargets = {
      "غنم",
      "غنم كبه",
      "ريش غنم",
      "سينتا شوي",
      "شوي كعب فخذ",
      "فيليه",
    };
    return cutTargets.contains(name);
  }

  Future<void> _addFromButton(String name) async {
    if (name == "صفايح كفته") {
      final res = await showDialog<OrderItem>(
        context: context,
        builder: (_) => const KoftaDialog(),
      );
      if (res != null) setState(() => items.add(res));
      return;
    }
    if (name == "شاورما") {
      final res = await showDialog<OrderItem>(
        context: context,
        builder: (_) => const ShawarmaDialog(),
      );
      if (res != null) setState(() => items.add(res));
      return;
    }
    if (name == "كباب") {
      final res = await showDialog<OrderItem>(
        context: context,
        builder: (_) => const KababDialog(),
      );
      if (res != null) setState(() => items.add(res));
      return;
    }
    if (name == "برغر") {
      final res = await showDialog<OrderItem>(
        context: context,
        builder: (_) => const BurgerDialog(),
      );
      if (res != null) setState(() => items.add(res));
      return;
    }
    if (_needsCutDialog(name)) {
      final res = await showDialog<OrderItem>(
        context: context,
        builder: (_) => CutDialog(baseName: name),
      );
      if (res != null) setState(() => items.add(res));
      return;
    }

    setState(
      () => items.add(
        OrderItem(name: name, valueType: ItemValueType.kg, kg: 1.0),
      ),
    );
  }

  Future<void> _addManual() async {
    final res = await showDialog<OrderItem>(
      context: context,
      builder: (_) => const ManualItemDialog(),
    );
    if (res != null) setState(() => items.add(res));
  }

  void _removeItem(int idx) {
    if (idx < 0 || idx >= items.length) return;
    setState(() {
      items.removeAt(idx);
      for (final c in noteCtrls.values) c.dispose();
      noteCtrls.clear();
    });
  }
  Future<void> _save() async {
    final customer = nameCtrl.text.trim();
    if (customer.isEmpty || items.isEmpty) return;

    // save notes
    for (int i = 0; i < items.length; i++) {
      items[i].note = noteCtrls[i]?.text.trim();
    }

    // validate time
    if (isFuture && scheduledFor == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("اختر التاريخ والوقت للطلب المستقبلي")),
      );
      return;
    }

    if (!isFuture && pickupAt == null) {
      pickupAt = DateTime.now().add(const Duration(minutes: 15));
    }

    final total = widget.store.calcOrderTotal(items);

    final order = Order(
      customer: customer,
      phone: phoneCtrl.text.trim(),
      pickupAt: isFuture ? null : pickupAt,
      scheduledFor: isFuture ? scheduledFor : null,
      items: items.map((e) => e.copy()).toList(),
      service: service,
      totalShekel: total,
      paidShekel: 0,
    );

    await widget.store.addOrder(order);

    // reset form
    nameCtrl.clear();
    phoneCtrl.clear();
    isFuture = false;
    scheduledFor = null;
    pickupAt = null;
    service = ServiceType.pickup;

    items.clear();
    for (final c in noteCtrls.values) {
      c.dispose();
    }
    noteCtrls.clear();

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("تم حفظ الطلب")));
  }
  

  @override
  Widget build(BuildContext context) {
    final total = widget.store.calcOrderTotal(items);

    return LayoutBuilder(
      builder: (context, c) {
        final isTablet = c.maxWidth >= 900;

        // Phone layout
        if (!isTablet) {
          final bottom = MediaQuery.of(context).viewInsets.bottom;
          return ListView(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: 12,
              bottom: bottom + 90,
            ),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Autocomplete<String>(
                        optionsBuilder: (v) {
                          final q = v.text.trim().toLowerCase();
                          if (q.isEmpty) return const Iterable<String>.empty();
                          return widget.store.customerNames
                              .where((n) => n.toLowerCase().startsWith(q))
                              .take(8);
                        },
                        onSelected: (s) {
                          nameCtrl.text = s;
                          widget.store.rememberCustomer(s);
                        },
                        fieldViewBuilder: (context, cc, f, _) {
                          cc.text = nameCtrl.text;
                          cc.selection = TextSelection.fromPosition(
                            TextPosition(offset: cc.text.length),
                          );
                          return TextField(
                            controller: cc,
                            focusNode: f,
                            decoration: const InputDecoration(
                              labelText: "اسم الزبون",
                            ),
                            keyboardType: TextInputType.name,
                            textInputAction: TextInputAction.done,
                            autocorrect: false,
                            enableSuggestions: false,
                            onChanged: (v) {
                              nameCtrl.text = v;
                              widget.store.rememberCustomer(v);
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: phoneCtrl,
                        decoration: const InputDecoration(
                          labelText: "هاتف (اختياري)",
                        ),
                        keyboardType: TextInputType.phone,
                      ),

                      const SizedBox(height: 10),
                      // ✅ Only show total (no payment UI)
                      Align(
                        alignment: Alignment.centerRight,
                        child: MoneyPill(text: "المجموع ₪ $total"),
                      ),

                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: _addManual,
                          icon: const Icon(Icons.edit_note),
                          label: const Text(
                            "إضافة صنف يدوي",
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (items.isNotEmpty)
                        ...items.asMap().entries.map((e) {
                          final idx = e.key;
                          final it = e.value;
                          noteCtrls[idx] ??= TextEditingController(
                            text: it.note ?? "",
                          );
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          it.titleLine,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => _removeItem(idx),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                  TextField(
                                    controller: noteCtrls[idx],
                                    decoration: const InputDecoration(
                                      labelText: "ملاحظة",
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text(
                    "حفظ الطلب",
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          );
        }

        // Tablet POS layout
        return Row(
          children: [
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _LeftInfoPanelNoPayment(
                  store: widget.store,
                  nameCtrl: nameCtrl,
                  phoneCtrl: phoneCtrl,
                  totalShekel: total,
                  service: service,
                  onService: (s) => setState(() => service = s),
                  isFuture: isFuture,
                  onFuture: (v) {
                    setState(() {
                      isFuture = v;
                      pickupAt = null;
                      scheduledFor = null;
                    });
                  },
                  pickupAt: pickupAt,
                  scheduledFor: scheduledFor,
                  onPickTodayDur: (dur) =>
                      setState(() => pickupAt = DateTime.now().add(dur)),
                  onPickTodayDateTime: (dt) => setState(() => pickupAt = dt),
                  onPickFuture: (dt) => setState(() => scheduledFor = dt),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 8,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _CategoryBar(
                      cats: _cats,
                      selected: _selectedCat,
                      onSelect: (v) => setState(() => _selectedCat = v),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            flex: 7,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _selectedCat,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        SizedBox(
                                          height: 44,
                                          child: OutlinedButton.icon(
                                            onPressed: _addManual,
                                            icon: const Icon(Icons.edit_note),
                                            label: const Text(
                                              "إضافة يدوي",
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Expanded(
                                      child: GridView.builder(
                                        itemCount:
                                            (productGroups[_selectedCat] ??
                                                    const <String>[])
                                                .length,
                                        gridDelegate:
                                            const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 3,
                                              mainAxisSpacing: 10,
                                              crossAxisSpacing: 10,
                                              childAspectRatio: 2.2,
                                            ),
                                        itemBuilder: (_, i) {
                                          final name =
                                              productGroups[_selectedCat]![i];
                                          return _ProductCard(
                                            title: name,
                                            onTap: () async {
                                              await _addFromButton(name);
                                              if (mounted) setState(() {});
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 5,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          "السلة",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const Spacer(),
                                        MoneyPill(text: "₪ $total"),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Expanded(
                                      child: items.isEmpty
                                          ? const Center(
                                              child: Text(
                                                "الطلب فارغ",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            )
                                          : ListView.separated(
                                              itemCount: items.length,
                                              separatorBuilder: (_, __) =>
                                                  const Divider(height: 12),
                                              itemBuilder: (_, idx) {
                                                final it = items[idx];
                                                noteCtrls[idx] ??=
                                                    TextEditingController(
                                                      text: it.note ?? "",
                                                    );
                                                return _CartItemRow(
                                                  item: it,
                                                  noteCtrl: noteCtrls[idx]!,
                                                  onDelete: () =>
                                                      _removeItem(idx),
                                                  onKgMinus: () => setState(() {
                                                    if (it.valueType !=
                                                        ItemValueType.kg)
                                                      return;
                                                    final current =
                                                        it.kg ?? 1.0;
                                                    if (current > 0.5)
                                                      it.kg = current - 0.5;
                                                  }),
                                                  onKgPlus: () => setState(() {
                                                    if (it.valueType !=
                                                        ItemValueType.kg)
                                                      return;
                                                    final current =
                                                        it.kg ?? 1.0;
                                                    it.kg = current + 0.5;
                                                  }),
                                                  onSwitchType: (t) => setState(
                                                    () => it.setValueType(t),
                                                  ),
                                                  onAmountChanged: (v) =>
                                                      setState(() {
                                                        final val =
                                                            int.tryParse(
                                                              v.trim(),
                                                            );
                                                        if (val == null) return;
                                                        it.amount = val;
                                                        it.valueType =
                                                            ItemValueType
                                                                .amount;
                                                      }),
                                                );
                                              },
                                            ),
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      height: 58,
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: _save,
                                        icon: const Icon(Icons.save),
                                        label: const Text(
                                          "حفظ وإنهاء الطلب",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/* ===========================
   Tablet helper widgets
=========================== */

class _CategoryBar extends StatelessWidget {
  final List<String> cats;
  final String selected;
  final ValueChanged<String> onSelect;

  const _CategoryBar({
    required this.cats,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final c = cats[i];
          final sel = c == selected;
          return SizedBox(
            height: 54,
            child: sel
                ? FilledButton(
                    onPressed: () => onSelect(c),
                    child: Text(
                      c,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  )
                : OutlinedButton(
                    onPressed: () => onSelect(c),
                    child: Text(
                      c,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _ProductCard({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.primary.withOpacity(0.18)),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.primary.withOpacity(0.25)),
              ),
              child: Icon(Icons.add, color: cs.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItemRow extends StatelessWidget {
  final OrderItem item;
  final TextEditingController noteCtrl;
  final VoidCallback onDelete;
  final VoidCallback onKgMinus;
  final VoidCallback onKgPlus;
  final void Function(ItemValueType) onSwitchType;
  final void Function(String) onAmountChanged;

  const _CartItemRow({
    required this.item,
    required this.noteCtrl,
    required this.onDelete,
    required this.onKgMinus,
    required this.onKgPlus,
    required this.onSwitchType,
    required this.onAmountChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.titleLine,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SegmentedButton<ItemValueType>(
          segments: const [
            ButtonSegment(value: ItemValueType.none, label: Text("بدون")),
            ButtonSegment(value: ItemValueType.kg, label: Text("وزن")),
            ButtonSegment(value: ItemValueType.amount, label: Text("سعر")),
          ],
          selected: {item.valueType},
          onSelectionChanged: (s) => onSwitchType(s.first),
        ),
        const SizedBox(height: 8),
        if (item.valueType == ItemValueType.kg)
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: onKgMinus,
                icon: const Icon(Icons.remove),
                label: const Text("0.5-"),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onKgPlus,
                icon: const Icon(Icons.add),
                label: const Text("0.5+"),
              ),
              const SizedBox(width: 10),
              Expanded(child: CompactValuePill(text: item.valueText)),
            ],
          ),
        if (item.valueType == ItemValueType.amount)
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: "₪ السعر"),
                  keyboardType: TextInputType.number,
                  onChanged: onAmountChanged,
                ),
              ),
              const SizedBox(width: 10),
              CompactValuePill(text: item.valueText),
            ],
          ),
        if (item.valueType == ItemValueType.none)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: CompactValuePill(text: item.valueText),
          ),
        const SizedBox(height: 10),
        TextField(
          controller: noteCtrl,
          decoration: const InputDecoration(labelText: "ملاحظة (اختياري)"),
        ),
      ],
    );
  }
}

class _LeftInfoPanel extends StatelessWidget {
  final OrdersStore store;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController paidCtrl;
  final int totalShekel;

  final ServiceType service;
  final ValueChanged<ServiceType> onService;

  final bool isFuture;
  final ValueChanged<bool> onFuture;

  final DateTime? pickupAt;
  final DateTime? scheduledFor;

  final void Function(Duration) onPickTodayDur;
  final void Function(DateTime) onPickTodayDateTime;
  final void Function(DateTime) onPickFuture;

  const _LeftInfoPanel({
    required this.store,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.paidCtrl,
    required this.totalShekel,
    required this.service,
    required this.onService,
    required this.isFuture,
    required this.onFuture,
    required this.pickupAt,
    required this.scheduledFor,
    required this.onPickTodayDur,
    required this.onPickTodayDateTime,
    required this.onPickFuture,
  });

  @override
  Widget build(BuildContext context) {
    final paid = int.tryParse(paidCtrl.text.trim()) ?? 0;
    final status = paid >= totalShekel ? "دفع" : "لم يدفع";

    return SingleChildScrollView(
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      "بيانات الطلب",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Autocomplete<String>(
                    optionsBuilder: (v) {
                      final q = v.text.trim().toLowerCase();
                      if (q.isEmpty) return const Iterable<String>.empty();
                      return store.customerNames
                          .where((n) => n.toLowerCase().startsWith(q))
                          .take(10);
                    },
                    onSelected: (s) {
                      nameCtrl.text = s;
                      store.rememberCustomer(s);
                    },
                    fieldViewBuilder: (context, c, f, _) {
                      c.text = nameCtrl.text;
                      c.selection = TextSelection.fromPosition(
                        TextPosition(offset: c.text.length),
                      );
                      return TextField(
                        controller: c,
                        focusNode: f,
                        decoration: const InputDecoration(
                          labelText: "اسم الزبون",
                        ),
                        keyboardType: TextInputType.name,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        enableSuggestions: false,
                        onChanged: (v) {
                          nameCtrl.text = v;
                          store.rememberCustomer(v);
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: "رقم الهاتف (اختياري)",
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      "طريقة الطلب",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<ServiceType>(
                    segments: const [
                      ButtonSegment(
                        value: ServiceType.pickup,
                        label: Text("استلام"),
                      ),
                      ButtonSegment(
                        value: ServiceType.delivery,
                        label: Text("توصيل"),
                      ),
                    ],
                    selected: {service},
                    onSelectionChanged: (s) => onService(s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "وقت الاستلام",
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text("اليوم")),
                      ButtonSegment(value: true, label: Text("مستقبلي")),
                    ],
                    selected: {isFuture},
                    onSelectionChanged: (s) => onFuture(s.first),
                  ),
                  const SizedBox(height: 12),
                  if (!isFuture)
                    _TodayTimeChips(
                      onPick: onPickTodayDur,
                      onPickDateTime: onPickTodayDateTime,
                      selected: pickupAt,
                    ),
                  if (isFuture)
                    _FuturePicker(value: scheduledFor, onPick: onPickFuture),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "الدفع",
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      MoneyPill(text: "المجموع ₪ $totalShekel"),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: paidCtrl,
                          decoration: const InputDecoration(
                            labelText: "₪ المدفوع",
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "الحالة: $status",
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

/* ===========================
   LIAH SCREEN + EDIT
=========================== */

class LiahScreen extends StatefulWidget {
  final OrdersStore store;
  const LiahScreen({super.key, required this.store});

  @override
  State<LiahScreen> createState() => _LiahScreenState();
}

class _LiahScreenState extends State<LiahScreen> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.store.liahOrders;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text(
                      "لا توجد طلبات لِيّة",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final o = list[i];
                      return Card(
                        child: ListTile(
                          title: Text(
                            o.name,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(o.phone.isEmpty ? "-" : o.phone),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                o.qty,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              IconButton(
                                tooltip: "تعديل",
                                onPressed: () async {
                                  final edited =
                                      await showModalBottomSheet<LiahOrder>(
                                        context: context,
                                        isScrollControlled: true,
                                        showDragHandle: true,
                                        builder: (_) =>
                                            EditLiahSheet(initial: o),
                                      );
                                  if (edited != null) {
                                    await widget.store.updateLiah(i, edited);
                                  }
                                },
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: "حذف",
                                onPressed: () async =>
                                    await widget.store.removeLiah(o),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: () async {
                final res = await showModalBottomSheet<LiahOrder>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => const AddLiahSheet(),
                );
                if (res != null) {
                  await widget.store.addLiah(res);
                }
              },
              icon: const Icon(Icons.add),
              label: const Text(
                "إضافة طلب لِيّة",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AddLiahSheet extends StatefulWidget {
  const AddLiahSheet({super.key});

  @override
  State<AddLiahSheet> createState() => _AddLiahSheetState();
}

class _AddLiahSheetState extends State<AddLiahSheet> {
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: "5 كغم");

  @override
  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        bottom: bottom + 14,
        top: 10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: "اسم الزبون"),
            keyboardType: TextInputType.name,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: phoneCtrl,
            decoration: const InputDecoration(labelText: "هاتف"),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: qtyCtrl,
            decoration: const InputDecoration(
              labelText: "الكمية (مثال: 5 كغم)",
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: () {
                final n = nameCtrl.text.trim();
                if (n.isEmpty) return;
                Navigator.pop(
                  context,
                  LiahOrder(
                    name: n,
                    phone: phoneCtrl.text.trim(),
                    qty: qtyCtrl.text.trim().isEmpty
                        ? "-"
                        : qtyCtrl.text.trim(),
                  ),
                );
              },
              child: const Text(
                "حفظ",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EditLiahSheet extends StatefulWidget {
  final LiahOrder initial;
  const EditLiahSheet({super.key, required this.initial});

  @override
  State<EditLiahSheet> createState() => _EditLiahSheetState();
}

class _EditLiahSheetState extends State<EditLiahSheet> {
  late TextEditingController nameCtrl;
  late TextEditingController phoneCtrl;
  late TextEditingController qtyCtrl;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.initial.name);
    phoneCtrl = TextEditingController(text: widget.initial.phone);
    qtyCtrl = TextEditingController(text: widget.initial.qty);
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        bottom: bottom + 14,
        top: 10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "تعديل طلب اللِيّة",
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: "اسم الزبون"),
            keyboardType: TextInputType.name,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: phoneCtrl,
            decoration: const InputDecoration(labelText: "هاتف"),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: qtyCtrl,
            decoration: const InputDecoration(
              labelText: "الكمية (مثال: 5 كغم)",
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              icon: const Icon(Icons.save),
              onPressed: () {
                final n = nameCtrl.text.trim();
                if (n.isEmpty) return;
                Navigator.pop(
                  context,
                  LiahOrder(
                    name: n,
                    phone: phoneCtrl.text.trim(),
                    qty: qtyCtrl.text.trim().isEmpty
                        ? "-"
                        : qtyCtrl.text.trim(),
                  ),
                );
              },
              label: const Text(
                "حفظ التعديل",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeftInfoPanelNoPayment extends StatelessWidget {
  final OrdersStore store;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final int totalShekel;

  final ServiceType service;
  final ValueChanged<ServiceType> onService;

  final bool isFuture;
  final ValueChanged<bool> onFuture;

  final DateTime? pickupAt;
  final DateTime? scheduledFor;

  final void Function(Duration) onPickTodayDur;
  final void Function(DateTime) onPickTodayDateTime;
  final void Function(DateTime) onPickFuture;

  const _LeftInfoPanelNoPayment({
    required this.store,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.totalShekel,
    required this.service,
    required this.onService,
    required this.isFuture,
    required this.onFuture,
    required this.pickupAt,
    required this.scheduledFor,
    required this.onPickTodayDur,
    required this.onPickTodayDateTime,
    required this.onPickFuture,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      "بيانات الطلب",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Autocomplete<String>(
                    optionsBuilder: (v) {
                      final q = v.text.trim().toLowerCase();
                      if (q.isEmpty) return const Iterable<String>.empty();
                      return store.customerNames
                          .where((n) => n.toLowerCase().startsWith(q))
                          .take(10);
                    },
                    onSelected: (s) {
                      nameCtrl.text = s;
                      store.rememberCustomer(s);
                    },
                    fieldViewBuilder: (context, c, f, _) {
                      c.text = nameCtrl.text;
                      c.selection = TextSelection.fromPosition(
                        TextPosition(offset: c.text.length),
                      );
                      return TextField(
                        controller: c,
                        focusNode: f,
                        decoration: const InputDecoration(
                          labelText: "اسم الزبون",
                        ),
                        keyboardType: TextInputType.name,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        enableSuggestions: false,
                        onChanged: (v) {
                          nameCtrl.text = v;
                          store.rememberCustomer(v);
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: "رقم الهاتف (اختياري)",
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      "طريقة الطلب",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<ServiceType>(
                    segments: const [
                      ButtonSegment(
                        value: ServiceType.pickup,
                        label: Text("استلام"),
                      ),
                      ButtonSegment(
                        value: ServiceType.delivery,
                        label: Text("توصيل"),
                      ),
                    ],
                    selected: {service},
                    onSelectionChanged: (s) => onService(s.first),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "وقت الاستلام",
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text("اليوم")),
                      ButtonSegment(value: true, label: Text("مستقبلي")),
                    ],
                    selected: {isFuture},
                    onSelectionChanged: (s) => onFuture(s.first),
                  ),
                  const SizedBox(height: 12),
                  if (!isFuture)
                    _TodayTimeChips(
                      onPick: onPickTodayDur,
                      onPickDateTime: onPickTodayDateTime,
                      selected: pickupAt,
                    ),
                  if (isFuture)
                    _FuturePicker(value: scheduledFor, onPick: onPickFuture),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ✅ Show total only (no payment)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      "المجموع",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  MoneyPill(text: "₪ $totalShekel"),
                ],
              ),
            ),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

/* ===========================
   PRICES SCREEN
   - Stable controllers (no reset on rebuild)
   - Save button (persist all)
=========================== */

class PricesScreen extends StatefulWidget {
  final OrdersStore store;
  const PricesScreen({super.key, required this.store});

  @override
  State<PricesScreen> createState() => _PricesScreenState();
}

class _PricesScreenState extends State<PricesScreen> {
  final Map<String, TextEditingController> _ctrls = {};

  @override
  void initState() {
    super.initState();
    widget.store.meatPrices.addListener(_onPrices);
    _buildControllersFromStore();
  }

  void _onPrices() {
    if (!mounted) return;
    // keep UI updated if prices changed from elsewhere
    setState(() {});
  }

  void _buildControllersFromStore() {
    final meat = meatItemsForPricing().toList()..sort();
    for (final name in meat) {
      final current = widget.store.meatPrices.getPrice(name);
      _ctrls[name] ??= TextEditingController(
        text: current == 0 ? "" : current.toString(),
      );
    }
  }

  @override
  void dispose() {
    widget.store.meatPrices.removeListener(_onPrices);
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _ctrls.clear();
    super.dispose();
  }

  Future<void> _saveAllPrices() async {
    final meat = meatItemsForPricing().toList()..sort();

    for (final name in meat) {
      final txt = _ctrls[name]?.text.trim() ?? "";
      final val = int.tryParse(txt) ?? 0;
      await widget.store.meatPrices.setPrice(name, val);
    }

    // recalc totals everywhere
    await widget.store.updateOrder();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("تم حفظ الأسعار ✅")));
  }

  @override
  Widget build(BuildContext context) {
    final meat = meatItemsForPricing().toList()..sort();
    _buildControllersFromStore();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text(
                "ضع سعر لكل صنف (₪ لكل كغم)",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              ...meat.map((name) {
                final ctrl = _ctrls[name]!;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 160,
                          child: TextField(
                            controller: ctrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "₪/كغم",
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              const Text(
                "ملاحظة: بعد حفظ الأسعار، يتم تحديث مجموع الطلبات تلقائياً.",
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),

        // Save button 
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _saveAllPrices,
              icon: const Icon(Icons.save),
              label: const Text(
                "حفظ الأسعار",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ],
    );
  }
}



/* ===========================
   HISTORY SCREEN
   - Paid toggle ONLY here (manual)
   - Default is "دفع"
=========================== */

class HistoryScreen extends StatefulWidget {
  final OrdersStore store;
  const HistoryScreen({super.key, required this.store});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.store.history;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "يتم حذف السجل تلقائياً بعد ${OrdersStore.historyKeepDays} أيام",
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: list.isEmpty
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text(
                              "مسح السجل",
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            content: const Text("هل تريد حذف كل السجل؟"),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text("إلغاء"),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text("حذف"),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await widget.store.clearHistory();
                        }
                      },
                icon: const Icon(Icons.delete_sweep),
                label: const Text("مسح"),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text(
                      "السجل فارغ",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final h = list[i];
                      final o = h.order;

                      // keep total updated
                      final total = widget.store.calcOrderTotal(o.items);
                      o.totalShekel = total;

                      final paidText = h.paidManual ? "دفع" : "لم يدفع";

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      o.customer,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: "حذف من السجل",
                                    onPressed: () async => await widget.store
                                        .deleteHistoryEntry(h),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              Text(
                                "انتهى: ${formatDateTimeShort(h.finishedAt)}",
                                style: const TextStyle(color: Colors.black54),
                              ),
                              const SizedBox(height: 10),

                              // total + manual paid label
                              Row(
                                children: [
                                  MoneyPill(text: "₪ ${o.totalShekel}"),
                                  const SizedBox(width: 10),
                                  MoneyPill(text: paidText),
                                ],
                              ),

                              const SizedBox(height: 10),

                              // toggle row (history only)
                              Row(
                                children: [
                                  const Text(
                                    "دفع؟",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Switch(
                                    value: h.paidManual,
                                    onChanged: (v) async {
                                      await widget.store.setHistoryPaid(h, v);
                                    },
                                  ),
                                ],
                              ),

                              const SizedBox(height: 8),
                              ...o.items.map(
                                (it) => OrderItemRowCompact(it: it),
                              ),
                            ],
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
}
