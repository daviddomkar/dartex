library dartex;

import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Mixin that every Dartex component uses.
///
/// Components compose [Entity] and describe its attributes.
/// You can modify component data using [System]s
///
/// You have to implement copy method so Dartex can internally copy your components
/// when moving entities across [Archetype]s
mixin Component<T> {
  @required
  T copy();

  T copyWith() {
    return copy();
  }
}

mixin Resource<T> {}

class EntityRecord {
  final Archetype type;

  int _row;
  int _version;

  EntityRecord({@required this.type, @required int row, @required int version})
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

  int _addEntity(int index, HashMap<Type, Component> componentMap) {
    var entries = componentMap.entries.toList();

    for (int i = 0; i < type.length; i++) {
      _components[entries[i].key].add(entries[i].value.copy());
    }

    _entities.add(index);

    return _entities.length - 1;
  }

  Component _replaceComponent<T extends Component>(int index, T component) {
    final oldComponent = _components[T][index].copy();
    _components[T][index] = component.copy();
    return oldComponent;
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
  Archetype add;
  Archetype remove;

  Edge({this.add, this.remove});
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

abstract class WorldEvent {
  final Type componentType;
  final Entity entity;

  WorldEvent(this.entity, this.componentType);
}

class ComponentAddedEvent extends WorldEvent {
  ComponentAddedEvent({
    @required Entity entity,
    @required Type componentType,
  }) : super(entity, componentType);
}

class ComponentReplacedEvent<T extends Component> extends WorldEvent {
  final T oldComponent;

  ComponentReplacedEvent({
    @required Entity entity,
    @required Type componentType,
    @required this.oldComponent,
  }) : super(entity, componentType);
}

class ComponentRemovedEvent<T extends Component> extends WorldEvent {
  final T removedComponent;

  ComponentRemovedEvent({
    @required Entity entity,
    @required Type componentType,
    @required this.removedComponent,
  }) : super(entity, componentType);
}

class World {
  final List<System> _systems;
  final HashMap<int, EntityRecord> _entities;
  final List<Archetype> _archetypes;
  final HashMap<Type, Resource> _resources;
  final List<Function(WorldEvent)> _eventListeners;

  int _nextEntityIndex = 0;

  World({@required List<System> systems})
      : _systems = systems,
        _entities = HashMap(),
        _archetypes = List(),
        _resources = HashMap(),
        _eventListeners = List();

  void addEventListener(Function(WorldEvent) listener) {
    _eventListeners.add(listener);
  }

  void removeEventListener(Function(WorldEvent) listener) {
    _eventListeners.remove(listener);
  }

  void _dispatchEvent(WorldEvent event) {
    _eventListeners.forEach((listener) {
      listener(event);
    });
  }

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

    int row = type._addEntity(index, componentMap);

    _entities[index] = EntityRecord(
      type: type,
      row: row,
      version: type.version,
    );

    final entity = Entity._(this, index);

    componentMap.keys.forEach((key) {
      _dispatchEvent(ComponentAddedEvent(
        entity: Entity._(this, entity.id),
        componentType: key,
      ));
    });

    return entity;
  }

  void _addComponent<T extends Component>(Entity entity, T component) {
    final record = _entities[entity.id];

    Archetype type;

    // Get or create new entity archetype
    if (record.type.edges.containsKey(T) && record.type.edges[T].add != null) {
      type = record.type.edges[T].add;
    } else {
      Function eq = const UnorderedIterableEquality().equals;

      type = _archetypes.firstWhere(
          (archetype) => eq(archetype.type, [...record.type.type, T]),
          orElse: () => _createArchetype([...record.type.type, T]));

      if (record.type.edges.containsKey(T)) {
        record.type.edges[T].add = type;
      } else {
        record.type.edges[T] = Edge(add: type);
      }
    }

    // Add new component
    final components = entity.components;
    components[T] = component;

    // Add entity to new archetype
    int row = type._addEntity(entity.id, components);

    // Update or create entity index
    _entities[entity.id] = EntityRecord(
      type: type,
      row: row,
      version: type.version,
    );

    if (record.version != record.type.version) {
      record._row = record.type.entities.indexOf(entity.id);
      record._version = record.type.version;
    }

    record.type._removeEntity(record.row);

    // If archetype has no entities, destroy it
    if (record.type.entities.isEmpty) {
      _archetypes.remove(record.type);
    }

    _dispatchEvent(ComponentAddedEvent(
      entity: Entity._(this, entity.id),
      componentType: T,
    ));
  }

  void _replaceComponent<T extends Component>(Entity entity, T component) {
    if (!entity.hasComponent<T>()) {
      _addComponent(entity, component);
      return;
    }

    final record = _entities[entity.id];

    final oldComponent = record.type._replaceComponent(record.row, component);

    _dispatchEvent(ComponentReplacedEvent<T>(
      entity: Entity._(this, entity.id),
      componentType: T,
      oldComponent: oldComponent,
    ));
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
    final removedComponent = components[T].copy();

    components.remove(T);

    int row = type._addEntity(entity.id, components);

    _entities[entity.id] = EntityRecord(
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

    _dispatchEvent(ComponentRemovedEvent<T>(
      entity: Entity._(this, entity.id),
      componentType: T,
      removedComponent: removedComponent,
    ));
  }

  void addResource<T extends Resource>(T resource) {
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
          var test = innerType.firstWhere(
              (element) => archetype.type.contains(element),
              orElse: () => null);

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
  HashMap<int, EntityRecord> get entities => _entities;
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

  void addComponent<T extends Component>(T component) {
    _world._addComponent(this, component);
  }

  void replaceComponent<T extends Component>(T component) {
    _world._replaceComponent<T>(this, component);
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
