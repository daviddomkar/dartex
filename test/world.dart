import 'package:dartex/component.dart';
import 'package:dartex/world.dart';
import 'package:test/test.dart';

class FooComponent implements Component {
  int foo = 0;
}

class BarComponent implements Component {
  int bar = 0;
}

class BazComponent implements Component {
  int baz = 0;
}

void main() {
  test('Query world for entity', () {
    World world = new World(
      systems: [],
    );

    world.registerComponent<FooComponent>();
    world.registerComponent<BarComponent>();
    world.registerComponent<BazComponent>();

    world
        .createEntity()
        .withComponent(FooComponent())
        .withComponent(BarComponent())
        .build();
    world
        .createEntity()
        .withComponent(FooComponent())
        .withComponent(BarComponent())
        .withComponent(BazComponent())
        .build();
    world
        .createEntity()
        .withComponent(FooComponent())
        .withComponent(BazComponent())
        .build();

    expect(world.query([FooComponent]).length, 3);
    expect(world.query([FooComponent, BarComponent]).length, 2);
    expect(world.query([FooComponent, BarComponent, BazComponent]).length, 1);
  });
}
