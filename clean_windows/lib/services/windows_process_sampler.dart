import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'process_utils.dart';

/// One owned worker emits snapshots each second while the module is active.
class WindowsProcessSampler {
  WindowsProcessSampler(this.script);
  final String script;
  Process? _process;
  Future<void>? _starting;
  StreamSubscription<String>? _stdout;
  StreamSubscription<String>? _stderr;
  Completer<PsResult>? _reply;
  PsResult? _latest;
  bool _closed = false;

  Future<void> _start() => _starting ??= _open();
  Future<void> _open() async {
    final command =
        '''
[Console]::OutputEncoding = New-Object Text.UTF8Encoding(\$false)
while (\$true) {
  \$watch = [Diagnostics.Stopwatch]::StartNew()
  try {
    \$payload = & {
$script
    }
    [Console]::WriteLine([string]\$payload)
  } catch {
    [Console]::WriteLine('{"Error":"process snapshot failed"}')
  }
  [Threading.Thread]::Sleep([int][math]::Max(10, 1000 - \$watch.ElapsedMilliseconds))
}
''';
    final process = await Process.start('powershell', [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      command,
    ]);
    if (_closed) {
      process.kill();
      throw StateError('进程采样已暂停');
    }
    _process = process;
    _stdout = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final text = line.replaceFirst('\uFEFF', '').trim();
          if (text.isEmpty) return;
          final failed = text.startsWith('{"Error":');
          final result = PsResult(
            exitCode: failed ? 1 : 0,
            stdout: failed ? '' : text,
            stderr: failed ? '无法读取进程列表' : '',
          );
          final pending = _reply;
          if (pending != null && !pending.isCompleted) {
            pending.complete(result);
          } else {
            _latest = result;
          }
        }, onError: (Object error) => _fail());
    _stderr = process.stderr.transform(utf8.decoder).listen((_) {});
    unawaited(
      process.exitCode.then((_) {
        if (identical(_process, process)) {
          _process = null;
          _fail();
        }
      }),
    );
  }

  void _fail() {
    final pending = _reply;
    if (pending != null && !pending.isCompleted) {
      pending.complete(PsResult(exitCode: 1, stdout: '', stderr: '进程采样已停止'));
    }
  }

  Future<PsResult> sample() async {
    if (_closed) throw StateError('进程采样已暂停');
    await _start();
    final process = _process;
    if (process == null) throw StateError('进程采样不可用');
    if (_latest != null) {
      final result = _latest!;
      _latest = null;
      return result;
    }
    if (_reply != null) return _reply!.future;
    final pending = Completer<PsResult>();
    _reply = pending;
    try {
      return await pending.future.timeout(const Duration(seconds: 6));
    } on TimeoutException {
      await close();
      return PsResult(exitCode: 1, stdout: '', stderr: '读取进程超时');
    } finally {
      if (identical(_reply, pending)) _reply = null;
    }
  }

  Future<void> close() async {
    _closed = true;
    final process = _process;
    _process = null;
    _fail();
    process?.kill(); // Only the helper process owned by this sampler.
    await _stdout?.cancel();
    await _stderr?.cancel();
  }
}
