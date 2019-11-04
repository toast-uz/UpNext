/*
   UpNext Configuration
   Copyright (c) 2019 Tatsuzo Osawa
   All rights reserved. This program and the accompanying materials
   are made available under the terms of the MIT License:
   https://opensource.org/licenses/mit-license.php
*/

import 'package:simple_logger/simple_logger.dart';

// optimizing option
// Config config = Config.auto();
Config config = Config.finalRelease();

class Config {
  final int gpsMode; // real, replay, pseudo
  final int timeMode; // real, virtual
  final bool verbose;
  int accumulateAPI;
  bool waitAPI;  // Temporary wait to call API
  static const int waitAPISeconds = 5;
  int countAPI;

  static const int gpsRealtime = 0;
  static const int gpsReplay = 1;
  static const int gpsPseudo = 2;
  static const int timeReal = 0;
  static const int timeVirtual = 1;
  bool get isGpsRealtime => gpsMode == gpsRealtime;
  bool get isGpsReplay => gpsMode == gpsReplay;
  bool get isGpsPseudo => gpsMode == gpsPseudo;
  bool get isGpsReal => gpsMode != gpsPseudo;
  bool get isTimeReal => timeMode == timeReal;
  bool get isTimeVirtual => timeMode == timeVirtual;

  static const int fastViewLimit = 5;  // abort counter for calling API

  Config({int gpsMode, int timeMode, this.verbose = false}) :
      gpsMode = gpsMode ?? gpsRealtime,
      timeMode = (gpsMode == gpsRealtime ? timeReal : (timeMode ?? timeVirtual))
  {
    accumulateAPI = 0;
    countAPI = 0;
    waitAPI = false;
    logger.formatter = (info) => '${info.level}'
//        ',${info.time}'
        '[${info.callerFrame ?? 'caller info not available'}] '
        '${info.message}';
  }
  factory Config.finalRelease() {
    logger.setLevel(
      Level.OFF,
      includeCallerInfo: false,
    );
    return Config();
  }

  factory Config.auto() {
    if (bool.fromEnvironment('dart.vm.product')) {
      // release mode
      logger.setLevel(
        Level.INFO,
        includeCallerInfo: true,
      );
      return Config(
        gpsMode: gpsPseudo,
//        timeMode: timeReal,
        verbose: true,
      );
    } else {
      // debug mode
      logger.setLevel(
        Level.INFO,
        includeCallerInfo: false,
      );
      return Config(
        gpsMode: gpsReplay,
//        timeMode: timeReal,
        verbose: true
      );
    }
  }
  resetAPI() {countAPI = 0;}
  addAPI() {countAPI++; accumulateAPI++;}
  bool get abort {
    bool result = (fastViewLimit < countAPI);
    if (result) logger.info(
        'API count is exceeded! count:$countAPI > max:$fastViewLimit');
    return result;
  }
}

final logger = SimpleLogger()..mode = LoggerMode.print;

