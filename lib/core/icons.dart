// Katalog ikon & warna yang bisa dipilih untuk pos, dompet, dan target.
// Ikon disimpan di database sebagai kunci teks supaya tetap valid walau
// versi Flutter berubah.

import 'package:flutter/material.dart';

const appIcons = <String, IconData>{
  'savings': Icons.savings_rounded,
  'food': Icons.restaurant_rounded,
  'coffee': Icons.local_cafe_rounded,
  'home': Icons.home_rounded,
  'bolt': Icons.bolt_rounded,
  'wifi': Icons.wifi_rounded,
  'phone': Icons.smartphone_rounded,
  'car': Icons.directions_car_rounded,
  'moto': Icons.two_wheeler_rounded,
  'fuel': Icons.local_gas_station_rounded,
  'bus': Icons.directions_bus_rounded,
  'cart': Icons.shopping_cart_rounded,
  'bag': Icons.shopping_bag_rounded,
  'game': Icons.sports_esports_rounded,
  'movie': Icons.movie_rounded,
  'health': Icons.favorite_rounded,
  'medical': Icons.medical_services_rounded,
  'fitness': Icons.fitness_center_rounded,
  'people': Icons.people_alt_rounded,
  'child': Icons.child_care_rounded,
  'pet': Icons.pets_rounded,
  'school': Icons.school_rounded,
  'book': Icons.menu_book_rounded,
  'gift': Icons.card_giftcard_rounded,
  'charity': Icons.volunteer_activism_rounded,
  'travel': Icons.flight_rounded,
  'beach': Icons.beach_access_rounded,
  'shirt': Icons.checkroom_rounded,
  'beauty': Icons.spa_rounded,
  'tools': Icons.build_rounded,
  'receipt': Icons.receipt_long_rounded,
  'credit': Icons.credit_card_rounded,
  'loan': Icons.request_quote_rounded,
  'shield': Icons.shield_rounded,
  'work': Icons.work_rounded,
  'laptop': Icons.laptop_mac_rounded,
  'trend': Icons.trending_up_rounded,
  'store': Icons.storefront_rounded,
  'cash': Icons.payments_rounded,
  'bank': Icons.account_balance_rounded,
  'wallet': Icons.account_balance_wallet_rounded,
  'emergency': Icons.health_and_safety_rounded,
  'house': Icons.house_rounded,
  'ring': Icons.diamond_rounded,
  'category': Icons.category_rounded,
};

IconData iconFor(String key) => appIcons[key] ?? Icons.category_rounded;

// 8 warna pertama = palet kategorikal yang sudah divalidasi (mudah dibedakan,
// termasuk untuk buta warna). Sisanya variasi tambahan.
const appColors = <int>[
  0xFF2A78D6, // biru
  0xFFEB6834, // oranye
  0xFF1BAF7A, // hijau toska
  0xFFEDA100, // kuning
  0xFFE87BA4, // magenta
  0xFF008300, // hijau
  0xFF4A3AA7, // ungu
  0xFFE34948, // merah
  0xFF0EA5E9, // biru langit
  0xFF8B5CF6, // violet
  0xFF14B8A6, // teal
  0xFF84CC16, // lime
  0xFF64748B, // abu-abu
];
