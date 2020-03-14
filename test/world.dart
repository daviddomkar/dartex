import 'package:dartex/dartex.dart';
import 'package:test/test.dart';

class Foo with Component<Foo> {
  int foo = 0;

  @override
  Foo copy() {
    return Foo();
  }

  @override
  Foo copyWith() {
    return Foo();
  }
}

class Bar with Component<Bar> {
  int bar = 0;

  @override
  Bar copy() {
    return Bar();
  }

  @override
  Bar copyWith() {
    return Bar();
  }
}

class Baz with Component<Baz> {
  int baz = 0;

  @override
  Baz copy() {
    return Baz();
  }

  @override
  Baz copyWith() {
    return Baz();
  }
}

void main() {
  test('Query world for entity', () {
    World world = new World(
      systems: [],
    );

    world.createEntity().withComponent(Foo()).withComponent(Bar()).build();
    world
        .createEntity()
        .withComponent(Foo())
        .withComponent(Bar())
        .withComponent(Baz())
        .build();
    var idk =
        world.createEntity().withComponent(Foo()).withComponent(Baz()).build();

    expect(world.query([Foo]).entities.length, 3);
    expect(world.query([Foo, Bar]).entities.length, 2);
    expect(world.query([Foo, Bar, Baz]).entities.length, 1);

    idk.removeComponent<Foo>();

    expect(world.query([Foo]).entities.length, 2);
  });
}
