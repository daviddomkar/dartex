import 'dart:collection';

import 'package:dartex/component.dart';
import 'package:dartex/resource.dart';
import 'package:dartex/system.dart';
import 'package:meta/meta.dart';

class World {
  final List<System> _systems;
  final HashMap<Type, HashMap<int, Component>> _componentMap;
  final HashMap<Type, Resource> _resourceMap;

  int _nextEntityIndex = 0;

  World({@required List<System> systems})
      : _systems = systems,
        _componentMap = HashMap(),
        _resourceMap = HashMap();

  void registerComponent(Type component) {
    _componentMap[component] = new HashMap();
  }

  void insertResource<T extends Resource>(T resource) {
    _resourceMap[T] = resource;
  }

  T getResource<T extends Resource>() {
    return _resourceMap[T];
  }

  void removeResource<T extends Resource>() {
    _resourceMap.remove(T);
  }

  EntityBuilder createEntity() {
    return EntityBuilder._(this);
  }

  void _createEntity(HashMap<Type, Component> componentMap) {
    componentMap.forEach(
        (type, component) => _componentMap[type][_nextEntityIndex] = component);

    _nextEntityIndex++;
  }

  void _insertComponent<T extends Component>(Entity entity, T component) {
    _componentMap[T][entity.id] = component;
  }

  void _removeComponent<T extends Component>(Entity entity) {
    _componentMap[T].remove(entity.id);
  }

  List<Entity> query(List<Type> componentTypes) {
    return componentTypes
        .skip(1)
        .fold<List<int>>(_componentMap[componentTypes[0]].keys.toList(),
            (prev, element) {
          return prev
              .where((id) => _componentMap[element].containsKey(id))
              .toList();
        })
        .map<Entity>(
          (id) => Entity._(this, id),
        )
        .toList();
  }

  void run() {
    _systems.forEach((system) => system.run(this, query(system.components)));
  }

  void clear() {
    _resourceMap.clear();
    _componentMap.clear();
    _systems.clear();
  }
}

class EntityBuilder {
  final World world;

  final HashMap<Type, Component> _componentMap;

  EntityBuilder._(this.world) : _componentMap = HashMap();

  EntityBuilder withComponent<T extends Component>(T component) {
    _componentMap[T] = component;
    return this;
  }

  void build() {
    world._createEntity(_componentMap);
  }
}

class Entity {
  final int id;
  final World _world;

  Entity._(this._world, this.id);

  T getComponent<T extends Component>() {
    return _world._componentMap[T][id];
  }

  void insertComponent<T extends Component>(T component) {
    _world._insertComponent(this, component);
  }

  void removeComponent<T extends Component>() {
    _world._removeComponent<T>(this);
  }
}
