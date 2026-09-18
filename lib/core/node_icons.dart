import 'package:flutter/material.dart';

/// Kartın adının önündeki simge için seçenekler. Anahtarlar kayıtla birlikte
/// saklanır ve eşitlenir; burada olmayan bir anahtar (ör. daha yeni bir
/// sürümden) gelirse türün varsayılan simgesi gösterilir.
class NodeIconGroup {
  const NodeIconGroup(this.tr, this.en, this.icons);

  final String tr;
  final String en;
  final Map<String, IconData> icons;

  String label(Locale locale) => locale.languageCode == 'tr' ? tr : en;
}

abstract final class NodeIcons {
  static const groups = <NodeIconGroup>[
    NodeIconGroup('Kutular ve çantalar', 'Boxes and bags', {
      'box': Icons.inventory_2_rounded,
      'archive': Icons.archive_rounded,
      'inbox': Icons.all_inbox_rounded,
      'briefcase': Icons.work_rounded,
      'backpack': Icons.backpack_rounded,
      'luggage': Icons.luggage_rounded,
      'bag': Icons.shopping_bag_rounded,
      'basket': Icons.shopping_basket_rounded,
      'gift': Icons.redeem_rounded,
      'takeout': Icons.takeout_dining_rounded,
    }),
    NodeIconGroup('Odalar ve yerler', 'Rooms and places', {
      'home': Icons.home_rounded,
      'kitchen': Icons.kitchen_rounded,
      'bed': Icons.bed_rounded,
      'bath': Icons.bathtub_rounded,
      'sofa': Icons.weekend_rounded,
      'garage': Icons.garage_rounded,
      'balcony': Icons.balcony_rounded,
      'yard': Icons.yard_rounded,
      'stairs': Icons.stairs_rounded,
      'door': Icons.door_front_door_rounded,
      'office': Icons.meeting_room_rounded,
      'roof': Icons.roofing_rounded,
    }),
    NodeIconGroup('Mobilya', 'Furniture', {
      'shelves': Icons.shelves,
      'table': Icons.table_restaurant_rounded,
      'chair': Icons.chair_rounded,
      'desk': Icons.desk_rounded,
      'wardrobe': Icons.checkroom_rounded,
      'lamp': Icons.light_rounded,
      'window': Icons.window_rounded,
      'bar': Icons.table_bar_rounded,
    }),
    NodeIconGroup('Mutfak', 'Kitchen', {
      'dining': Icons.restaurant_rounded,
      'coffee': Icons.local_cafe_rounded,
      'blender': Icons.blender_rounded,
      'soup': Icons.soup_kitchen_rounded,
      'microwave': Icons.microwave_rounded,
      'cutlery': Icons.flatware_rounded,
      'wine': Icons.wine_bar_rounded,
      'bottle': Icons.liquor_rounded,
      'egg': Icons.egg_rounded,
      'cake': Icons.cake_rounded,
      'bowl': Icons.rice_bowl_rounded,
    }),
    NodeIconGroup('Aletler', 'Tools', {
      'tools': Icons.build_rounded,
      'handyman': Icons.handyman_rounded,
      'construction': Icons.construction_rounded,
      'hardware': Icons.hardware_rounded,
      'carpenter': Icons.carpenter_rounded,
      'plumbing': Icons.plumbing_rounded,
      'electric': Icons.electrical_services_rounded,
      'paint': Icons.format_paint_rounded,
      'cleaning': Icons.cleaning_services_rounded,
      'iron': Icons.iron_rounded,
      'scissors': Icons.content_cut_rounded,
      'ruler': Icons.straighten_rounded,
    }),
    NodeIconGroup('Elektronik', 'Electronics', {
      'devices': Icons.devices_rounded,
      'laptop': Icons.laptop_rounded,
      'phone': Icons.phone_android_rounded,
      'tv': Icons.tv_rounded,
      'headphones': Icons.headphones_rounded,
      'camera': Icons.photo_camera_rounded,
      'game': Icons.videogame_asset_rounded,
      'cable': Icons.cable_rounded,
      'battery': Icons.battery_charging_full_rounded,
      'power': Icons.power_rounded,
      'router': Icons.router_rounded,
      'printer': Icons.print_rounded,
      'speaker': Icons.speaker_rounded,
    }),
    NodeIconGroup('Kitap ve belge', 'Books and papers', {
      'book': Icons.menu_book_rounded,
      'stories': Icons.auto_stories_rounded,
      'library': Icons.library_books_rounded,
      'folder': Icons.folder_rounded,
      'document': Icons.description_rounded,
      'note': Icons.edit_note_rounded,
      'school': Icons.school_rounded,
      'mail': Icons.mail_rounded,
      'calculator': Icons.calculate_rounded,
    }),
    NodeIconGroup('Giyim ve bakım', 'Clothes and care', {
      'hanger': Icons.dry_cleaning_rounded,
      'jewelry': Icons.diamond_rounded,
      'watch': Icons.watch_rounded,
      'umbrella': Icons.umbrella_rounded,
      'medical': Icons.medical_services_rounded,
      'pills': Icons.medication_rounded,
      'bandage': Icons.healing_rounded,
      'spa': Icons.spa_rounded,
      'soap': Icons.soap_rounded,
    }),
    NodeIconGroup('Hobi ve spor', 'Hobbies and sports', {
      'football': Icons.sports_soccer_rounded,
      'basketball': Icons.sports_basketball_rounded,
      'fitness': Icons.fitness_center_rounded,
      'bike': Icons.pedal_bike_rounded,
      'music': Icons.music_note_rounded,
      'piano': Icons.piano_rounded,
      'art': Icons.palette_rounded,
      'brush': Icons.brush_rounded,
      'toys': Icons.toys_rounded,
      'puzzle': Icons.extension_rounded,
      'hiking': Icons.hiking_rounded,
      'pool': Icons.pool_rounded,
    }),
    NodeIconGroup('Bahçe ve hayvanlar', 'Garden and pets', {
      'flower': Icons.local_florist_rounded,
      'grass': Icons.grass_rounded,
      'tree': Icons.park_rounded,
      'eco': Icons.eco_rounded,
      'pets': Icons.pets_rounded,
      'water': Icons.water_drop_rounded,
    }),
    NodeIconGroup('Yolculuk', 'Travel', {
      'car': Icons.directions_car_rounded,
      'motorbike': Icons.two_wheeler_rounded,
      'flight': Icons.flight_rounded,
      'beach': Icons.beach_access_rounded,
      'map': Icons.map_rounded,
      'tent': Icons.cabin_rounded,
    }),
    NodeIconGroup('Diğer', 'Other', {
      'tag': Icons.label_rounded,
      'offer': Icons.local_offer_rounded,
      'star': Icons.star_rounded,
      'heart': Icons.favorite_rounded,
      'bolt': Icons.bolt_rounded,
      'bulb': Icons.lightbulb_rounded,
      'key': Icons.key_rounded,
      'lock': Icons.lock_rounded,
      'piggy': Icons.savings_rounded,
      'party': Icons.celebration_rounded,
      'baby': Icons.child_friendly_rounded,
      'category': Icons.category_rounded,
    }),
  ];

  static final Map<String, IconData> _all = {
    for (final g in groups) ...g.icons,
  };

  static IconData? byKey(String? key) => key == null ? null : _all[key];

  static bool isKnown(String? key) => key != null && _all.containsKey(key);
}
