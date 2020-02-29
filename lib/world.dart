import 'dart:collection';

import 'package:dartex/component.dart';
import 'package:dartex/system.dart';

class World {
  final List<System> _systems;
  final HashMap<Type, HashMap<int, Component>> _componentMap;

  World({List<System> systems})
      : _systems = systems ?? [],
        _componentMap = HashMap();

  addSystem(System system) {
    if (_systems.contains(system)) {
      print(
          "[DARTEX]: Warning: System is already added and will be updated more than once!");
    }

    _systems.add(system);
  }
}
