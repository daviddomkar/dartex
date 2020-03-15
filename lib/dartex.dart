library dartex;

import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

mixin Component<T> {
  @required
  T copy();

  T copyWith() {
    return copy();
  }
}

mixin Resource<T> {}

class Record {
  final Archetype type;

  int _row;
  int _version;

  Record({@required this.type, @required int row, @required int version})
      : _row = row,
        _version = version;

  int get row => _row;
  int get version => _version;
}

class Archetype {
  final List<int> _entities;
  final HashMap<Type, List<Component>> _components;
  final HashMap<Type, Edge> _edges;

  int _version;

  Archetype({@required List<Type> type})
      : _entities = List(),
        _components = HashMap(),
        _edges = HashMap(),
        _version = 0 {
    type.forEach((element) {
      _components[element] = List();
    });
  }

  int _insertEntity(int index, HashMap<Type, Component> componentMap) {
    var entries = componentMap.entries.toList();

    for (int i = 0; i < type.length; i++) {
      _components[entries[i].key].add(entries[i].value.copy());
    }

    _entities.add(index);

    return _entities.length - 1;
  }

  void _removeEntity(int index) {
    _entities.removeAt(index);

    _components.values.forEach((array) {
      array.removeAt(index);
    });

    _version++;
  }

  Iterable<Type> get type => _components.keys;

  List<int> get entities => _entities;
  HashMap<Type, List<Component>> get components => _components;
  HashMap<Type, Edge> get edges => _edges;

  int get version => _version;
}

class Edge {
  Archetype insert;
  Archetype remove;

  Edge({this.insert, this.remove});
}

class System {
  final List<dynamic> _type;

  QueryResult _cache;

  System({@required List<dynamic> type}) : _type = type;

  void run(World world, List<Entity> entities) {}

  List<dynamic> get type => _type;
}

class QueryResult {
  final List<int> versions;
  final List<Entity> entities;

  QueryResult({@required this.versions, @required this.entities});
}

class World {
  final List<System> _systems;
  final HashMap<int, Record> _entities;
  final List<Archetype> _archetypes;
  final HashMap<Type, Resource> _resources;

  int _nextEntityIndex = 0;

  World({@required List<System> systems})
      : _systems = systems,
        _entities = HashMap(),
        _archetypes = List(),
        _resources = HashMap();

  Archetype _createArchetype(List<Type> type) {
    final archetype = Archetype(type: [...type]);
    _archetypes.add(archetype);
    return archetype;
  }

  int _createEntityIndex() {
    final index = _nextEntityIndex;
    _nextEntityIndex++;
    return index;
  }

  Entity _createEntity(HashMap<Type, Component> componentMap) {
    Function eq = const UnorderedIterableEquality().equals;

    Archetype type = _archetypes.firstWhere(
        (archetype) => eq(archetype.type, componentMap.keys),
        orElse: () => _createArchetype([...componentMap.keys]));

    final index = _createEntityIndex();

    int row = type._insertEntity(index, componentMap);

    _entities[index] = Record(
      type: type,
      row: row,
      version: type.version,
    );

    final entity = Entity._(this, index);
    return entity;
  }

  void _insertComponent<T extends Component>(Entity entity, T component) {
    final record = _entities[entity.id];

    Archetype type;

    if (record.type.edges.containsKey(T) &&
        record.type.edges[T].insert != null) {
      type = record.type.edges[T].insert;
    } else {
      Function eq = const UnorderedIterableEquality().equals;

      type = _archetypes.firstWhere(
          (archetype) => eq(archetype.type, [...record.type.type, T]),
          orElse: () => _createArchetype([...record.type.type, T]));

      if (record.type.edges.containsKey(T)) {
        record.type.edges[T].insert = type;
      } else {
        record.type.edges[T] = Edge(insert: type);
      }
    }

    final components = entity.components;
    components[T] = component;

    int row = type._insertEntity(entity.id, components);

    _entities[entity.id] = Record(
      type: type,
      row: row,
      version: type.version,
    );

    if (record.version != record.type.version) {
      record._row = record.type.entities.indexOf(entity.id);
      record._version = record.type.version;
    }

    record.type._removeEntity(record.row);

    if (record.type.entities.isEmpty) {
      _archetypes.remove(record.type);
    }
  }

  void _removeComponent<T extends Component>(Entity entity) {
    final record = _entities[entity.id];

    Archetype type;

    if (record.type.edges.containsKey(T) &&
        record.type.edges[T].remove != null) {
      type = record.type.edges[T].remove;
    } else {
      Function eq = const UnorderedIterableEquality().equals;

      final newType = [...record.type.type];
      newType.remove(T);

      type = _archetypes.firstWhere((archetype) => eq(archetype.type, newType),
          orElse: () => _createArchetype(newType));

      if (record.type.edges.containsKey(T)) {
        record.type.edges[T].remove = type;
      } else {
        record.type.edges[T] = Edge(remove: type);
      }
    }

    final components = entity.components;
    components.remove(T);

    int row = type._insertEntity(entity.id, components);

    _entities[entity.id] = Record(
      type: type,
      row: row,
      version: type.version,
    );

    if (record.version != record.type.version) {
      record._row = record.type.entities.indexOf(entity.id);
      record._version = record.type.version;
    }

    record.type._removeEntity(record.row);

    if (record.type.entities.isEmpty) {
      _archetypes.remove(record.type);
    }
  }

  void insertResource<T extends Resource>(T resource) {
    _resources[T] = resource;
  }

  T getResource<T extends Resource>() {
    return _resources[T];
  }

  void removeResource<T extends Resource>() {
    _resources.remove(T);
  }

  EntityBuilder createEntity() {
    return EntityBuilder._(this);
  }

  QueryResult query(List<dynamic> type, {QueryResult cache = null}) {
    final archetypes = _archetypes.where(
      (archetype) => type.every((innerType) {
        if (innerType is Type) {
          return archetype.type.contains(innerType);
        } else if (innerType is List<Type>) {
          var test = innerType
              .firstWhere((element) => archetype.type.contains(element));

          return test != null;
        }

        return false;
      }),
    );

    if (cache != null) {
      Function eq = const ListEquality().equals;
      if (eq(cache.versions, archetypes.map((type) => type.version).toList())) {
        return cache;
      }
    }

    return QueryResult(
        versions: archetypes.map((type) => type.version).toList(),
        entities: archetypes.fold(List<Entity>(), (array, archetype) {
          array.addAll(
              archetype.entities.map((entity) => Entity._(this, entity)));
          return array;
        }));
  }

  void run() {
    _systems.forEach((system) => system.run(this,
        (system._cache = query(system.type, cache: system._cache)).entities));
  }

  void destroy() {
    destroyEntities();
    destroyResources();
    _systems.clear();
  }

  void destroyEntities() {
    _archetypes.clear();
    _entities.clear();

    _systems.forEach((system) {
      system._cache = null;
    });
  }

  void destroyResources() {
    _resources.clear();
  }

  List<System> get systems => _systems;
  HashMap<int, Record> get entities => _entities;
  List<Archetype> get archetypes => _archetypes;
  HashMap<Type, Resource> get resources => _resources;
}

class EntityBuilder {
  final World world;

  final HashMap<Type, Component> _componentMap;

  EntityBuilder._(this.world) : _componentMap = HashMap();

  EntityBuilder withComponent<T extends Component>(T component) {
    _componentMap[T] = component;
    return this;
  }

  Entity build() {
    return world._createEntity(_componentMap);
  }
}

class Entity {
  final int id;
  final World _world;

  Entity._(this._world, this.id);

  T getComponent<T extends Component>() {
    final record = _world._entities[id];

    if (record.version != record.type.version) {
      record._row = record.type.entities.indexOf(id);
      record._version = record.type.version;
    }

    return record.type.components[T] != null
        ? record.type.components[T][record.row]
        : null;
  }

  bool hasComponent<T extends Component>() {
    final record = _world._entities[id];

    if (record.version != record.type.version) {
      record._row = record.type.entities.indexOf(id);
      record._version = record.type.version;
    }

    return record.type.components.containsKey(T);
  }

  void insertComponent<T extends Component>(T component) {
    _world._insertComponent(this, component);
  }

  void removeComponent<T extends Component>() {
    _world._removeComponent<T>(this);
  }

  HashMap<Type, Component> get components {
    final record = _world._entities[id];

    if (record.version != record.type.version) {
      record._row = record.type.entities.indexOf(id);
      record._version = record.type.version;
    }

    return HashMap.fromEntries(record.type.components.entries.map((entry) =>
        MapEntry<Type, Component>(entry.key, entry.value[record.row])));
  }
}
