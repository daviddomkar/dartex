import 'package:dartex/world.dart';

class System {
  final List<Type> _components;

  System(List<Type> components) : _components = components;

  void run(World world, List<Entity> entities) {}

  get components => _components;
}
