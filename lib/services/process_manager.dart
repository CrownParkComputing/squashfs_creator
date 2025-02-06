import 'dart:io';

class ProcessManager {
  static final Map<String, Process> _runningProcesses = {};

  static void registerProcess(String prefixPath, Process process) {
    _runningProcesses[prefixPath] = process;
  }

  static Future<void> killProcess(String prefixPath) async {
    final process = _runningProcesses[prefixPath];
    if (process != null) {
      try {
        process.kill();
        await process.exitCode;
      } catch (e) {
        print('Error killing process: $e');
      } finally {
        _runningProcesses.remove(prefixPath);
      }
    }
  }

  static bool isProcessRunning(String prefixPath) {
    return _runningProcesses.containsKey(prefixPath);
  }
} 