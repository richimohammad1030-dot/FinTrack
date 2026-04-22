// lib/providers/transaction_provider.dart
// Pro-Tracker - State Management
// Mengelola semua state transaksi menggunakan ChangeNotifier (Provider).

import 'package:flutter/foundation.dart';
import '../models/transaction_model.dart';
import '../database/database_helper.dart';

class TransactionProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();

  // ── State ────────────────────────────────────────────────────────────────
  List<TransactionModel> _transactions = [];
  List<TransactionModel> _recentTransactions = [];
  Map<String, double> _expenseByCategory = {};
  Map<String, double> _incomeByCategory = {};

  double _totalIncome = 0.0;
  double _totalExpense = 0.0;
  bool _isLoading = false;
  String? _error;

  // Filter state
  TransactionType? _activeTypeFilter;
  TransactionCategory? _activeCategoryFilter;

  // ── Getters ──────────────────────────────────────────────────────────────
  List<TransactionModel> get transactions => _transactions;
  List<TransactionModel> get recentTransactions => _recentTransactions;
  Map<String, double> get expenseByCategory => _expenseByCategory;
  Map<String, double> get incomeByCategory => _incomeByCategory;
  double get totalIncome => _totalIncome;
  double get totalExpense => _totalExpense;
  double get netBalance => _totalIncome - _totalExpense;
  bool get isLoading => _isLoading;
  String? get error => _error;
  TransactionType? get activeTypeFilter => _activeTypeFilter;
  TransactionCategory? get activeCategoryFilter => _activeCategoryFilter;

  /// Persentase pengeluaran terhadap pemasukan (0.0 - 1.0), untuk progress bar
  double get expenseRatio {
    if (_totalIncome == 0) return 0.0;
    return (_totalExpense / _totalIncome).clamp(0.0, 1.0);
  }

  /// List transaksi yang sudah difilter
  List<TransactionModel> get filteredTransactions {
    if (_activeTypeFilter == null && _activeCategoryFilter == null) {
      return _transactions;
    }
    return _transactions.where((t) {
      final typeMatch =
          _activeTypeFilter == null || t.type == _activeTypeFilter;
      final categoryMatch =
          _activeCategoryFilter == null || t.category == _activeCategoryFilter;
      return typeMatch && categoryMatch;
    }).toList();
  }

  // ── Inisialisasi ─────────────────────────────────────────────────────────

  /// Dipanggil sekali saat app pertama dibuka (dari main.dart via ..init())
  Future<void> init() async {
    await _loadAll();
  }

  /// Muat ulang semua data dari database
  Future<void> refresh() async {
    await _loadAll();
  }

  Future<void> _loadAll() async {
    _setLoading(true);
    try {
      await Future.wait([
        _loadTransactions(),
        _loadSummary(),
      ]);
      _error = null;
    } catch (e) {
      _error = 'Gagal memuat data: ${e.toString()}';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _loadTransactions() async {
    _transactions = await _db.getAllTransactions();
    _recentTransactions = await _db.getRecentTransactions(limit: 10);
  }

  Future<void> _loadSummary() async {
    _totalIncome = await _db.getTotalIncome();
    _totalExpense = await _db.getTotalExpense();
    _expenseByCategory = await _db.getExpenseByCategory();
    _incomeByCategory = await _db.getIncomeByCategory();
  }

  // ── CRUD Actions ─────────────────────────────────────────────────────────

  /// Tambah transaksi baru
  Future<bool> addTransaction(TransactionModel transaction) async {
    try {
      await _db.insertTransaction(transaction);
      await _loadAll();
      return true;
    } catch (e) {
      _error = 'Gagal menyimpan transaksi: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Update transaksi yang ada
  Future<bool> updateTransaction(TransactionModel transaction) async {
    try {
      await _db.updateTransaction(transaction);
      await _loadAll();
      return true;
    } catch (e) {
      _error = 'Gagal mengupdate transaksi: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Hapus transaksi berdasarkan id
  Future<bool> deleteTransaction(int id) async {
    try {
      await _db.deleteTransaction(id);
      await _loadAll();
      return true;
    } catch (e) {
      _error = 'Gagal menghapus transaksi: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Reset semua data (untuk keperluan development/testing)
  Future<void> clearAllData() async {
    await _db.deleteAllTransactions();
    await _loadAll();
  }

  // ── Filter ───────────────────────────────────────────────────────────────

  void setTypeFilter(TransactionType? type) {
    _activeTypeFilter = type;
    notifyListeners();
  }

  void setCategoryFilter(TransactionCategory? category) {
    _activeCategoryFilter = category;
    notifyListeners();
  }

  void clearFilters() {
    _activeTypeFilter = null;
    _activeCategoryFilter = null;
    notifyListeners();
  }

  // ── Helper ───────────────────────────────────────────────────────────────

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}