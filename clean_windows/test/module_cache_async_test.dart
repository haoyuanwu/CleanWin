import 'dart:io';

import 'package:clean_windows/services/module_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fixture;
  late ModuleCache cache;
  setUp(() {
    fixture = Directory('.dart_tool').createTempSync('async_cache_').absolute;
    cache = ModuleCache(namespace: 'snapshot', storageDirectory: fixture.path);
  });
  tearDown(() {
    expect(
      fixture.path.startsWith(
        '${Directory('.dart_tool').absolute.path}${Platform.pathSeparator}',
      ),
      isTrue,
    );
    fixture.deleteSync(recursive: true);
  });
  ModuleCache restored() =>
      ModuleCache(namespace: 'snapshot', storageDirectory: fixture.path);

  test('background snapshots persist and the newest snapshot wins', () async {
    final first = cache.setAsync('files', List.generate(5000, (i) => 'old-$i'));
    final second = cache.setAsync('files', ['new']);
    await Future.wait([first, second]);
    expect(restored().getList('files'), ['new']);
    expect(
      fixture.listSync().whereType<File>().where(
        (file) => file.path.endsWith('.tmp'),
      ),
      isEmpty,
    );
    expect(fixture.listSync().whereType<Directory>(), isEmpty);
  });

  test(
    'pending snapshots cannot undo a durable update, invalidate or clear',
    () async {
      for (var i = 0; i < 20; i++) {
        final write = cache.setAsync('files', ['old-$i']);
        cache.setDurable('files', ['saved-$i']);
        await write;
        expect(restored().getList('files'), ['saved-$i']);
      }
      var pending = cache.setAsync('files', ['old']);
      cache.invalidate('files');
      await pending;
      expect(restored().getList('files'), isNull);
      pending = cache.setAsync('files', ['old']);
      cache.clear();
      await pending;
      expect(restored().getList('files'), isNull);
    },
  );

  test('unwritable cache does not fail a completed operation', () async {
    final blocked = File('${fixture.path}/blocked')..writeAsStringSync('file');
    final cache = ModuleCache(storageDirectory: blocked.path);
    await cache.setAsync('files', ['remaining']);
    expect(cache.getList('files'), ['remaining']);
  });

  test('background durable save persists and reports failure without losing memory', () async {
    await cache.setDurableAsync('options', {'deepScan': true});
    expect(restored().getMap('options'), {'deepScan': true});
    final blocked = File('${fixture.path}/blocked')..writeAsStringSync('file');
    final denied = ModuleCache(storageDirectory: blocked.path);
    denied.set('options', {'deepScan': false});
    await expectLater(
      denied.setDurableAsync('options', {'deepScan': true}),
      throwsA(isA<FileSystemException>()),
    );
    expect(denied.getMap('options'), {'deepScan': false});
  });

  test('background invalidation keeps other ranges and supersedes pending snapshots', () async {
    cache.set('other-range', ['keep']);
    final pending = cache.setAsync(
      'files',
      List.generate(5000, (i) => 'file-$i'),
    );
    final invalidation = cache.invalidateAsync('files');
    expect(cache.getList('files'), isNull);
    await Future.wait([pending, invalidation]);
    expect(restored().getList('files'), isNull);
    expect(restored().getList('other-range'), ['keep']);
  });
}
