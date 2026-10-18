import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../models/clean_models.dart';
import 'file_safety.dart';

Future<String?> contentDigest(
  String path, {
  CleanCancellation? cancellation,
}) async {
  if (cancellation?.requested ?? false) return null;
  final port = ReceivePort();
  final result = Completer<String?>();
  SendPort? control;
  final detach = cancellation?.listen(() => control?.send('cancel'));
  final subscription = port.listen((message) {
    if (message is SendPort) {
      control = message;
      if (cancellation?.requested ?? false) control!.send('cancel');
    } else if (!result.isCompleted) {
      result.complete(message is String ? message : null);
    }
  });
  Isolate? worker;
  try {
    worker = await Isolate.spawn(
      _digestWorker,
      [port.sendPort, path],
      onError: port.sendPort,
      onExit: port.sendPort,
    );
    return await result.future;
  } finally {
    detach?.call();
    worker?.kill(priority: Isolate.immediate);
    await subscription.cancel();
    port.close();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

void _digestWorker(List<Object> arguments) async {
  final output = arguments[0] as SendPort;
  final path = arguments[1] as String;
  final control = ReceivePort();
  var cancelled = false;
  control.listen((_) => cancelled = true);
  output.send(control.sendPort);
  try {
    if (await hasLinkedAncestorAsync(path)) {
      output.send(null);
      return;
    }
    final file = File(path);
    final before = await file.stat();
    final digest = _DigestSink();
    final sink = sha256.startChunkedConversion(digest);
    await for (final bytes in file.openRead()) {
      if (cancelled) break;
      sink.add(bytes);
    }
    sink.close();
    final after = await file.stat();
    output.send(
      !cancelled && fileSignature(before) == fileSignature(after)
          ? digest.value?.toString()
          : null,
    );
  } catch (_) {
    output.send(null);
  } finally {
    control.close();
  }
}
