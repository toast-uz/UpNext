/*
   ODPT = Open Data for Public Transportation support classes for UpNext
   Copyright (c) 2019 Tatsuzo Osawa
   All rights reserved. This program and the accompanying materials
   are made available under the terms of the MIT License:
   https://opensource.org/licenses/mit-license.php
*/

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info/package_info.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tuple/tuple.dart';

import 'config.dart';
import 'config_secret.dart';
import 'location.dart';

const String base_uri ='https://api-tokyochallenge.odpt.org/api/v4/';

_OdptController odpt = _OdptController();

class _OdptController {
  static final _OdptController _singleton = _OdptController._();
  bool _doneInit;
  String _buildNumber;
  DateTime _lastSave;
  int _lastSaveAccumulateAPI;
  File _cacheFile;
  _Calendars calendars;
  _TrainTypes trainTypes;
  _Railways railways;
  _RailDirections railDirections;
  _Stations stations;
  _StationTimetables stationTimetables;
  _Trains trains;
  _TrainInformations trainInformations;
  _TrainTimetables trainTimetables;

  factory _OdptController() => _singleton;
  _OdptController._() {_doneInit = false;}

  init() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    _buildNumber = packageInfo.buildNumber;
    calendars = _Calendars();
    trainTypes = _TrainTypes();
    railways = _Railways();
    railDirections = _RailDirections();
    stations = _Stations();
    stationTimetables = _StationTimetables();
    trains = _Trains();
    trainInformations = _TrainInformations();
    trainTimetables = _TrainTimetables();
    _doneInit = true;
    _lastSave = DateTime.now();
    _lastSaveAccumulateAPI = 0;
    Directory tempDir = await getTemporaryDirectory();
    _cacheFile = File('${tempDir.path}/odpt.txt');
    assert(_cacheFile != null);
    await load();
  }

  fromJson(final Map<String, dynamic> json) {
    String buildNumber = json['buildNumber'];
    if ((buildNumber != null) && ((int.tryParse(buildNumber) ?? 0) >= 5)) {
      calendars.fromJson(json);
      trainTypes.fromJson(json);
      railways.fromJson(json);
      railDirections.fromJson(json);
      stations._fromJson(json);
      stationTimetables.fromJson(json);
      trainTimetables.fromJson(json);
      logger.info('Loaded cache completely.');
    } else {
      logger.warning('Unsupport the version of cache file. Start cleanly.');
    }
  }

  Map<String, dynamic> toJson() => {
    'odpt:Calendar': calendars,
    'odpt:TrainType': trainTypes,
    'odpt:Railway': railways,
    'odpt:RailDirection': railDirections,
    'odpt:Station': stations,
    'odpt:Station.circle': stations.circles.toList().cast<Circle>(),
    'odpt:Station.hit': stations.hit.toList().cast<int>(),
    'odpt:StationTimetable': stationTimetables,
    'odpt:TrainTimetable': trainTimetables,
    'buildNumber': _buildNumber,
    'DateTime': DateTime.now().toIso8601String(),
  };

  // Load permanent cache
  load() async {
    assert(_doneInit);
    if (!await _cacheFile.exists()) {
      logger.info('No cache file of ${_cacheFile.path}');
      return;
    }
    String fileData = await _cacheFile.readAsString();
    if ((fileData?.length == 0) ?? true) {
      logger.info('No content of the cache file of ${_cacheFile.path}');
      return;
    }
    try {
      fromJson(jsonDecode(fileData));
    } catch (e) {
      await _cacheFile.delete();
      logger.severe('Cache file ${_cacheFile.path} was broken. Deleted.');
    }
  }

  // Save permanent cache
  save() async {
    assert(_doneInit);
    // Avoid save frequently
    if ((config.accumulateAPI <= _lastSaveAccumulateAPI) ||
        (DateTime.now().difference(_lastSave).inSeconds  < 30)) return;

    _lastSave = DateTime.now();
    _lastSaveAccumulateAPI = config.accumulateAPI;
    if (await _cacheFile.exists()) {
      await _cacheFile.delete();
    } else {
      await _cacheFile.create(recursive: true);
      logger.info('Created a new cache file ${_cacheFile.path}');
    }
    try {
      String fileData = jsonEncode(this);
      if ((fileData?.length == 0) ?? true) {
        logger.warning('No content of the saving file ${_cacheFile.path}'
            ' Abort saving.');
        return;
      }
      await _cacheFile.writeAsString(fileData);
      logger.info('Saved cache to ${_cacheFile.path}');
    } catch (e) {
      logger.severe('Cannot save cache file ${_cacheFile.path}'
          ', due to ${e.toString()}');
    }
  }

// owl utility function class
  String _owlRailwayToOperator(final String owlRailway) {
    List<String> s = owlRailway?.split(':')?.last?.split('.') ?? [];
    if ((s?.length ?? 0 ) < 2) return null;
    return 'odpt.Operator:${s.first}';
  }
  String owlRailwayToTrainInformation(final String owlRailway) {
    List<String> s = owlRailway?.split(':')?.last?.split('.') ?? [];
    if ((s?.length ?? 0 ) < 2) return null;
    return 'odpt.TrainInformation:${s[0]}.${s[1]}';
  }
  String _owlTrainInformationShort(final String owlTrainInformation) {
    List<String> s = owlTrainInformation?.split(':')?.last?.split('.') ?? [];
    if ((s?.length ?? 0 ) < 2) return null;
    return 'odpt.TrainInformation:${s[0]}';
  }
  String _owlStationToRailway(final String owlStation) {
    List<String> s = owlStation?.split(':')?.last?.split('.') ?? [];
    if ((s?.length ?? 0 ) < 3) return null;
    return 'odpt.Railway:${s[0]}.${s[1]}';
  }
  String _owlTimetableToStation(final String owlTimetable) {
    List<String> s = owlTimetable?.split(':')?.last?.split('.') ?? [];
    if ((s?.length ?? 0 ) < 5) return null;
    return 'odpt.Station:${s.sublist(0, 3).join('.')}';
  }
  String _owlTimetableToRailDirection(final String owlTimetable) {
    List<String> s = owlTimetable?.split(':')?.last?.split('.') ?? [];
    if ((s?.length ?? 0 ) < 5) return null;
    return 'odpt.RailDirection:${s.sublist(3, s.length -1).join('.')}';
  }
  String _owlTimetableToRailway(final String owlTimetable) {
    List<String> s = owlTimetable?.split(':')?.last?.split('.') ?? [];
    if ((s?.length ?? 0 ) < 5) return null;
    return 'odpt.Railway:${s.sublist(0, 2).join('.')}';
  }
  String _owlTimetableToCalendar(final String owlTimetable) {
    List<String> s = owlTimetable?.split(':')?.last?.split('.') ?? [];
    if ((s?.length ?? 0 ) < 5) return null;
    return 'odpt.Calendar:${s.last}';
  }
  String _owlCreateVirtualTrainNumber(
      final String owlTimetable, final String id) {
    List<String> s = owlTimetable?.split(':')?.last?.split('.') ?? [];
    if ((s?.length ?? 0 ) < 5) return null;
    return '${s[2]}${s[3]}${s[4]}$id';
  }
  String _owlTimetableToTrain(
      final String owlTimetable, final String trainNumber) {
    List<String> s = owlTimetable?.split(':')?.last?.split('.') ?? [];
    if ((s?.length ?? 0 ) < 5) return null;
    return 'odpt.TrainTimetable:${s[0]}.${s[1]}.$trainNumber';
  }
  String _owlTimetableToTrainTimetable(
      final String owlTimetable, final String trainNumber) {
    List<String> s = owlTimetable?.split(':')?.last?.split('.') ?? [];
    if ((s?.length ?? 0 ) < 5) return null;
    return 'odpt.TrainTimetable:${s[0]}.${s[1]}.$trainNumber.${s[4]}';
  }
  String _owlTrainToTrainNumber(final String owlTrain) {
    List<String> s = owlTrain?.split(':')?.last?.split('.') ?? [];
    if ((s?.length ?? 0 ) < 3) return null;
    return '${s.last}';
  }
  String _owlCreateTimetable(final String owlStation, final String owlDirection,
      final String owlCalendar) {
    return 'odpt.StationTimetable:${owlStation?.split(':')?.last}.'
        '${owlDirection?.split(':')?.last}.${owlCalendar?.split(':')?.last}';
  }
  String owlCreateConnectingStation(final String owlStation,
      final String owlRailway) {
    List<String> s = owlRailway?.split(':')?.last?.split('.') ?? [];
    if ((s?.length ?? 0 ) < 2) return null;
    return 'odpt.Station:${s[0]}.${s[1]}.${_owlLast(owlStation)}';
  }
  String _owlLast(final String owl) {
    return '${owl?.split('.')?.last}';
  }
  Time _durationFromDistance(double distance) {
    int speed;
    if (distance >= 3000) {
      speed = 80;
    } else if (distance >= 2000) {
      speed = 65;
    } else {
      speed = 50;
    }
    return Time.fromSeconds(distance * 3.6 ~/ speed + 30);
  }
}

// odpt base object
@immutable
class Odpt {
  final bool isExist;
  final String owl;
  final String title;
  final DateTime expired;

  Odpt() : this._();
  Odpt._([this.isExist, this.owl, this.title, this.expired]);
  Odpt._clone(Odpt odpt) :
        isExist = odpt?.isExist, owl = odpt?.owl, title = odpt?.title,
        expired = odpt?.expired;
  Odpt clone() => Odpt._clone(this);
  Odpt._notExist() : this._(false);
  factory Odpt._fromJson(final Map<String, dynamic> json) {
    if (json == null) return null;
    return Odpt._(json['isExist'] ??= true, json['owl:sameAs'], json['dc:title'],
        json['dct:valid'] != null ?
        DateTime.tryParse(json['dct:valid']) : null);
  }
  Map<String, dynamic> toJson() {
    if ((owl == null) || (!isExist)) return null;
    return {'isExist': isExist, 'owl:sameAs': owl, 'dc:title': title,
      'dct:valid': expired?.toIso8601String()};
  }

  Odpt notExist() => Odpt._notExist();
  Odpt fromJson(final Map<String, dynamic> json) => Odpt._fromJson(json);
  bool get isValid => expired?.isAfter(DateTime.now()) ?? true;
  bool get isNotValid => expired?.isBefore(DateTime.now()) ?? false;

  @override
  String toString() => '$owl($title) exists $isExist, expired at $expired';
}

abstract class Odpts<T extends Odpt> {
  final Map<String, T> bases;
  final String queryName;
  final int _mode;
  final T t;

  static const int noCache = 0;
  static const int tempCache = 1;
  static const int permanentCache = 2;
  static const int getAll = 3;
  bool get _useCache => (_mode != noCache);
  bool get _getAll => _mode == getAll;

  Odpts(this.queryName, int mode, this.t) :
        _mode = (mode == noCache ? noCache :
        ((mode != getAll) ? mode : getAll)),
        bases = <String, T>{};

  Future<String> title(final String owl) async {
    final T odpt = await get(owl);
    return odpt?.title;
  }

  @override
  String toString() => '$queryName -> $bases';

  fromJson(final Map<String, dynamic> json) {
    final List<T> list = json[queryName]?.map((value) =>
        t.fromJson(value))?.toList()?.cast<T>();
    if (list?.isNotEmpty ?? false) {
      for (T type in list) {
        if (type != null) bases..putIfAbsent(type.owl, () => type);
      }
      logger.info('Added cache #${list.length} of ${t.runtimeType}.');
    }
  }
  List<Map<String, dynamic>> toJson() =>
      bases.values.map((value) => value.toJson()).toList();

  Future<T> get(final String owl) async {
    if (config.waitAPI) {
      await Future.delayed(Duration(seconds: Config.waitAPISeconds));
    }
    await odpt.save();
    if (owl == null) return null;
    if (_useCache && (bases[owl] != null)) {
      if (bases[owl].isExist) {
        logger.config('Hit cache :$owl in ${this.runtimeType}.');
        if ((_mode == tempCache) && bases[owl].isNotValid) {
          logger.config('but the cache had been expired.'
              ' expired: ${bases[owl].expired} < now: ${DateTime.now()}');
          bases.remove(owl);
        }
        return bases[owl];
      } else {
        logger.config('Hit cache :$owl in ${this.runtimeType},'
            ' but it is not found in the open data.');
        return null;
      }
    }
    if (_getAll && (bases?.isNotEmpty ?? false)) {
      logger.config('No cache :$owl in ${this.runtimeType},'
          'but already gotten all.');
      return null;
    }
    final String requestUri ='$base_uri$queryName?'
        '${_getAll ? '': 'owl:sameAs=$owl&'}'
        'acl:consumerKey=$apikey_opendata';
    logger.info('No cache : $owl in ${this.runtimeType} and getting '
        '${_getAll ? 'all': ''}: $requestUri at:${DateTime.now()}');
    http.Response response;
    try {
      config.addAPI();
      response = await http.get(requestUri).timeout(Duration(seconds: 10));
    } catch (e) {
      logger.severe(e.toString());
      return null;
    }
    logger.info('Got response at:${DateTime.now()}');
    if (response.statusCode == 429) {
      logger.warning('429: Too Many Requests on $queryName and wait'
          ' ${Config.waitAPISeconds} seconds.');
      config.waitAPI = true;
      // retry to call API
      T t = await get(owl);
      config.waitAPI = false;
      return t;
    } else if (response.statusCode == 200) {
      final List<T> list = [];
      final List<dynamic> decoded = json.decode(response.body);
      for (final item in decoded) {
        list.add(t.fromJson(item));
      }
      if (list.isNotEmpty) {
        logger.info('Succeeded on $queryName API.');
        if (_useCache) {
          for (T type in list) {
            bases..putIfAbsent(type.owl, () => type);
          }
          logger.info('Added cache #${list.length} of ${t.runtimeType}.');
          return bases[owl];
        } else {
          return list[0];
        }
      } else {
        logger.info('Succeeded but no content from $queryName API.');
        if (_useCache) {
          bases..putIfAbsent(owl, () => t.notExist());
          logger.info('Add cache as notExist from $queryName API.');
        }
        return null;
      }
    } else {
      logger.severe('Failed on $queryName API'
          ' with code ${response.statusCode} by $owl.');
      return null;
    }
  }
}

// rdf:type of odpt:Calendar
@immutable
class Calendar extends Odpt {
  Calendar() : this._();
  Calendar._([Odpt odpt]) : super._clone(odpt);

  @override
  Calendar notExist() => Calendar._(super.notExist());
  @override
  Calendar fromJson(final Map<String, dynamic> json) =>
      Calendar._(super.fromJson(json));
}

class _Calendars extends Odpts<Calendar> {
  _Calendars() : super('odpt:Calendar', Odpts.getAll, Calendar());

  Future<List<String>> getCandidateOwls(final Date date) async {
    const List<String> strWeekday = [
      'null', 'Monday', 'Tuesday', 'Wednesday',
      'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    const List<String> strHolidays = [
      '2019/1/1', '2019/1/14', '2019/2/11', '2019/3/21', '2019/4/29', '2019/4/30',
      '2019/5/1', '2019/5/2', '2019/5/3', '2019/5/4', '2019/5/5', '2019/5/6',
      '2019/7/15', '2019/8/11', '2019/8/12', '2019/9/16', '2019/9/23',
      '2019/10/14', '2019/10/22', '2019/11/3', '2019/11/4', '2019/11/23',
      '2020/1/1', '2020/1/13', '2020/2/11', '2020/2/23', '2020/2/24', '2020/3/20',
      '2020/4/29', '2020/5/3', '2020/5/4', '2020/5/5', '2020/5/6', '2020/7/23',
      '2020/7/24', '2020/8/10', '2020/9/21', '2020/9/22', '2020/11/3',
      '2020/11/23',
      '2021/1/1', '2021/1/11', '2021/2/11', '2021/2/23', '2021/3/20', '2021/4/29',
      '2021/5/3', '2021/5/4', '2021/5/5', '2021/7/19', '2021/8/11', '2021/9/20',
      '2021/9/23', '2021/10/11', '2021/11/3', '2021/11/23',
      '2022/1/1', '2022/1/10', '2022/2/11', '2022/2/23', '2022/3/21', '2022/4/29',
      '2022/5/3', '2022/5/4', '2022/5/5', '2022/7/18', '2022/8/11', '2022/9/19',
      '2022/9/23', '2022/10/10', '2022/11/3', '2022/11/23',
      // New Year's holiday
      '2019/1/2', '2019/1/3', '2019/12/29', '2019/12/30', '2019/12/31',
      '2020/1/2', '2020/1/3', '2020/12/29', '2020/12/30', '2020/12/31',
      '2021/1/2', '2021/1/3', '2021/12/29', '2021/12/30', '2021/12/31',
      '2022/1/2', '2022/1/3', '2022/12/29', '2022/12/30', '2022/12/31',
    ];

    List<String> candidate = [];
    int weekday = date.weekday;
    // is Sunday ?
    if (weekday == DateTime.sunday) {
      candidate.add('odpt.Calendar:${strWeekday[weekday]}');
      candidate.add('odpt.Calendar:Holiday');
      candidate.add('odpt.Calendar:SaturdayHoliday');
      return candidate;
    }
    // is Holiday and is not Sunday?
    if (strHolidays.contains('${date.year}/${date.month}/${date.day}')) {
      // Holiday is prior to Saturday
      candidate.add('odpt.Calendar:Holiday');
      candidate.add('odpt.Calendar:SaturdayHoliday');
      candidate.add('odpt.Calendar:${strWeekday[weekday]}');
      return candidate;
    }
    // is Saturday and is not Holiday?
    if (weekday == DateTime.saturday) {
      candidate.add('odpt.Calendar:${strWeekday[weekday]}');
      candidate.add('odpt.Calendar:SaturdayHoliday');
      return candidate;
    }
    // must be Weekday
    candidate.add('odpt.Calendar:${strWeekday[weekday]}');
    candidate.add('odpt.Calendar:Weekday');
    return candidate;
  }
}

// rdf:type of odpt:TrainType
@immutable
class TrainType extends Odpt {
  final String owlOperator;

  TrainType() : this._();
  TrainType._([Odpt base, this.owlOperator]) : super._clone(base);

  @override
  TrainType notExist() => TrainType._(super.notExist());
  @override
  TrainType fromJson(final Map<String, dynamic> json) =>
      TrainType._(super.fromJson(json), json['odpt:operator']);
  @override
  Map<String, dynamic> toJson() {
    Map<String, dynamic> map = super.toJson();
    map?.addAll({'odpt:operator': owlOperator});
    return map;
  }

  String get shortTitle {
    const Map<String, String> transfer = {
      '各駅停車' : '',
      '普通' : '',
      '快速急行' : '快急',
      '快速特急' : '快特',
      '快特' : '快特',
      '準特急' : '準特',
      '通勤準急' : '通準',
      '通勤急行' : '通急',
      '通勤特急' : '通特',
      '通勤快速' : '通快',
      '通勤特快' : '通特快',
      '特別快速' : '特快',
      '中央特快' : '特快',
      '区間準急' : '区準',
      '区間急行' : '区急',
      'エアポート急行' : '空急',
      'エアポート快特' : '空快',
      '快特ウィング' : '快翼',
      'アクセス特急' : '接特',
      'SL大樹' : 'SL',
      'TJライナー' : 'TJ',
    };
    String short = transfer[title];
    // If no match in transfer, take 1st multi-byte of title
    if (short == null) short = String.fromCharCode(title.runes.first);
    return short;
  }
}

class _TrainTypes extends Odpts<TrainType> {
  _TrainTypes() : super('odpt:TrainType', Odpts.getAll, TrainType());

  Future<String> shortTitle(final String owl) async {
    final TrainType trainType = await super.get(owl);
    return trainType?.shortTitle;
  }
}

// rdf:type of odpt:Railway
@immutable
class Railway extends Odpt {
  final String owlOperator;
  final List<String> owlStationOrders;
  final String owlAscendingRailDirection;
  final String owlDescendingRailDirection;

  Railway() : this._();
  Railway._([Odpt base, this.owlOperator, this.owlStationOrders,
    this.owlAscendingRailDirection, this.owlDescendingRailDirection]) :
        super._clone(base);

  @override
  Railway notExist() => Railway._(super.notExist());
  @override
  Railway fromJson(final Map<String, dynamic> json) =>
      Railway._(super.fromJson(json), json['odpt:operator'],
          json['odpt:stationOrder']?.map((value) =>
          value['odpt:station'])?.toList()?.cast<String>(),
          json['odpt:ascendingRailDirection'],
          json['odpt:descendingRailDirection']);
  @override
  Map<String, dynamic> toJson() {
    Map<String, dynamic> map = super.toJson();
    List<Map<String, dynamic>> stationOrders = [];
    int index = 1;
    if (owlStationOrders?.isNotEmpty ?? false) {
      for (String owlStation in owlStationOrders) {
        stationOrders.add({'odpt:index': index, 'odpt:station': owlStation});
        index++;
      }
    }
    map?.addAll({'odpt:operator': owlOperator,
      'odpt:stationOrder' : stationOrders,
      'odpt:ascendingRailDirection': owlAscendingRailDirection,
      'odpt:descendingRailDirection': owlDescendingRailDirection});
    return map;
  }

  // Care about Yamanote Line and Oedo Line
  // Oedo.TochoMae has two next stations for ascending!!
  List<String> owlNexts(final String owlStation, final AD ad) {
    if (ad == AD.undefined()) return null;
    final List<int> fromIndexList = [];
    for (int i = 0; i < owlStationOrders.length; i++) {
      i = owlStationOrders.indexWhere((item) => item == owlStation, i);
      if (i < 0) break;
      fromIndexList.add(i);
    }
    if (fromIndexList.isEmpty) return null;
    final List<String> toList = [];
    for (int i in fromIndexList) {
      int j = i + ad.stationOrderSign;
      if ((0 <= j) && (j < owlStationOrders.length)) {
        toList.add(owlStationOrders[j]);
      }
    }
    return toList;
  }

  // Get the next n-th stations (recursive)
  List<String> owlFollows(final String owlStation, final AD ad, int n) {
    List<String> result = [];
    if (n == 0) {
      result.add(owlStation);
    } else {
      for (String s in owlFollows(owlStation, ad, n - 1)) {
        result.addAll(owlNexts(s, ad));
      }
    }
    return result;
  }

  int originIndex(AD ad) {
    if (ad == AD.ascend()) {
      return 0;
    } else if (ad == AD.descend()) {
      return owlStationOrders.length - 1;
    }
    return -1;
  }
  int terminalIndex(AD ad ) => originIndex(AD.reversed(ad));
  bool isTerminalIndex(int index, AD ad) => index == terminalIndex(ad);
  bool isOriginIndex(int index, AD ad) => index == originIndex(ad);
  bool isValidIndex(int index) =>
    (0 <= index) && (index < owlStationOrders.length);

  // Care loop railway
  bool isTerminal(String station, AD ad) {
    return (owlNexts(station, ad)?.isEmpty ?? false);
  }

  String owlRailDirection(final AD ad) {
    if (ad.isAscend) {
      return owlAscendingRailDirection;
    } else if (ad.isDescend) {
      return owlDescendingRailDirection;
    }
    return null;
  }

  AD ad(final String owlRailDirection) {
    if (owlRailDirection == owlAscendingRailDirection) return AD.ascend();
    if (owlRailDirection == owlDescendingRailDirection) return AD.descend();
    return null;
  }
  int stationIndex(String owlStation, AD ad) {
    if (ad == AD.ascend()) {
      return owlStationOrders.indexWhere((item) => item == owlStation);
    } else if (ad == AD.descend()) {
      return owlStationOrders.lastIndexWhere((item) => item == owlStation);
    } else {
      return -1;
    }
  }
  bool isValidStation(String owlStation) =>
      ((owlStationOrders?.indexWhere((item) => item == owlStation) ?? -1) >= 0);
  Future<String> getRailDirectionTitle(final AD ad) async {
    return await odpt.railDirections.title(owlRailDirection(ad));
  }
  // Calc the distance between stations along the railway
  Future<double> distance(String from, String to, AD ad) async {
    if (!isValidStation(from)) return null;
    if (!isValidStation(to)) return null;
    double result = 0;
    Station stationA = await odpt.stations.get(from);
    if (stationA?.location?.isNotReady ?? true) return null;
    for (;;) {
      String owlNext = owlNexts(stationA.owl, ad)[0];
      Station stationB = await odpt.stations.get(owlNext);
      if (stationB?.location?.isNotReady ?? true) return null;
      result += (stationA.location - stationB.location).norm;
      if (stationB.owl == to) break;
      stationA = stationB;
    }
    return result;
  }

  // Get index of station from (by using station to)
  int index(String from, [String to]) {
    int indexFrom = owlStationOrders.indexOf(from);
    if ((indexFrom == -1) || (to == null)) return indexFrom;
    int indexTo = owlStationOrders.indexOf(to);
    if (indexTo == -1) return indexFrom;
    if ((indexFrom - indexTo).abs() == 1) return indexFrom;
    indexFrom = owlStationOrders.indexOf(from, indexFrom + 1);
    if ((indexFrom - indexTo).abs() == 1) return indexFrom;
    return -1;
  }
}

class _Railways extends Odpts<Railway> {
  _Railways() : super('odpt:Railway', Odpts.getAll, Railway());
}

// RailDirection support class
@immutable
class AD {
  final int _status;    //  ascend = 1, descend = -1, undefined = 0;
  static const int _ascend = 1;
  static const int _descend = -1;
  static const int _undefined = 0;

  AD._(this._status);
  AD.ascend() : this._(_ascend);
  AD.descend() : this._(_descend);
  AD.undefined() : this._(_undefined);
  AD.reversed(AD ad) : this._(-ad._status);
  AD() : this.undefined();

  @override
  String toString() => _status == _ascend ? 'ascend' :
  (_status == _descend ? 'descend' : 'unkonwn');
  @override
  int get hashCode => _status.hashCode;
  @override
  bool operator ==(other) => this._status == other._status;

  bool lazyEqual(other) =>
      (this == other) || (this == AD.undefined()) || (other == AD.undefined());
  bool get isAscend => this == AD.ascend();
  bool get isDescend => this == AD.descend();
  bool get isLazyAscend => this.lazyEqual(AD.ascend());
  bool get isLazyDescend => this.lazyEqual(AD.descend());
  int get stationOrderSign => _status;
}

// rdf:type of odpt:RailwayDirection
@immutable
class RailDirection extends Odpt {
  RailDirection() : this._();
  RailDirection._([Odpt base]) : super._clone(base);

  @override
  RailDirection notExist() => RailDirection._(super.notExist());
  @override
  RailDirection fromJson(final Map<String, dynamic> json) =>
      RailDirection._(super.fromJson(json));
}

class _RailDirections extends Odpts<RailDirection> {
  _RailDirections() :
        super('odpt:RailDirection', Odpts.getAll, RailDirection());
}

// rdf:type of odpt:Station
@immutable
class Station extends Odpt {
  final String owlOperator;
  final String owlRailway;
  final Location location;
  final List<String> owlStationTimetables;
  final List<String> owlConnectingRailway;

  Station() : this._();
  Station._([Odpt base, this.owlOperator, this.owlRailway, this.location,
    this.owlStationTimetables, this.owlConnectingRailway]) :
        super._clone(base);

  @override
  Station notExist() => Station._(super.notExist());
  @override
  Station fromJson(final Map<String, dynamic> json) {
    if (json == null) return null;
    return Station._(super.fromJson(json),
        json['odpt:operator'],
        json['odpt:railway'],
        (json['geo:lat'] == null) || (json['geo:long'] == null) ?
        null : Location.fromLatLng(json['geo:lat'], json['geo:long']),
        json['odpt:stationTimetable']?.toList()?.cast<String>(),
        json['odpt:connectingRailway']?.toList()?.cast<String>());
  }
  @override
  Map<String, dynamic> toJson() {
    Map<String, dynamic> map = super.toJson();
    map?.addAll({'odpt:operator': owlOperator,
      'odpt:railway' : owlRailway,
      'odpt:stationTimetable': owlStationTimetables,
      'odpt:connectingRailway': owlConnectingRailway});
    if (location?.isReady ?? false) {
      map?.addAll({'geo:lat': location?.latitude,
        'geo:long': location?.longitude});
    }
    return map;
  }
  @override
  String toString() => '${super.toString()}, $location';
  Future<List<String>> owlNexts(final AD ad) async {
    final Railway railway = await odpt.railways.get(this.owlRailway);
    return railway.owlNexts(owl, ad);
  }

  // Return expired timetables on the date :
  // + include terminal timetable (not include odptStationTimetables)
  // - exclude reverse direction
  // + include extra timetable at the last (Oedo Line)
  Future<List<String>> getExValidTimetables(Date date, [AD ad]) async {
    if (ad == null) ad = AD.undefined();
    String calendar = await getValidCalendar(date);
    if (calendar == null) return null;
    List<String> result = [];
    Railway railway = await odpt.railways.get(this.owlRailway);
    if (railway == null) return null;
    for (AD ad in [AD.ascend(), AD.descend()]) {
      // + include terminal timetable (not include odptStationTimetables)
      String direction = railway.owlRailDirection(ad);
      if (direction != null)
        result.add(odpt._owlCreateTimetable(owl, direction, calendar));
    }
    // + include extra timetable at the last (Oedo Line)
    if (owlStationTimetables != null) {
      final List<String> extraTimetables = [];
      extraTimetables.addAll(owlStationTimetables.where((item) =>
      odpt._owlTimetableToCalendar(item) == calendar));
      extraTimetables.removeWhere((item) => result?.contains(item) ?? false);
      if (extraTimetables?.isNotEmpty ?? false) result.addAll(extraTimetables);
    }
    // - exclude reverse direction
    String direction = railway.owlRailDirection(AD.reversed(ad));
    if (direction != null) {
      result.remove(odpt._owlCreateTimetable(owl, direction, calendar));
    }
    return result;
  }

  Future<String> getValidCalendar(final Date date) async {
    final List<String> owlCalendars =
    await odpt.calendars.getCandidateOwls(date);
    if (owlCalendars == null) return null;
    for (final String owlCalendar in owlCalendars) {
      if (owlStationTimetables?.any((item) =>
      odpt._owlTimetableToCalendar(item) == owlCalendar) ?? false) {
        return owlCalendar;
      }
    }
    return null;
  }

  Future<String> getValidCalenderTitle(final Date date) async {
    return odpt.calendars.title(await getValidCalendar(date));
  }

  // Detect terminal timetable
  bool isValidTimeTable(final String owlTimetable) {
    return owlStationTimetables.contains(owlTimetable);
  }

  // includes terminal timetable which has not the object of StationTimetable
  Future<String> getTimetableTitle(final String owlTimetable) async {
    String owlDirection = odpt._owlTimetableToRailDirection(owlTimetable);
    return await odpt.railDirections.title(owlDirection);
  }

  Future<List<String>> getConnectingRailwayTitles() async {
    final List<String> list = [];
    if (owlConnectingRailway == null) return list;
    for (String owlRailway in owlConnectingRailway) {
      final String title = await odpt.railways.title(owlRailway);
      if (title != null) list.add(title);
    }
    return list;
  }

  // Detect whether at the station
  isHere(Location location) {
    double distance = 200;
    if (owl == 'odpt.Station:JR-East.Keiyo.Tokyo') distance = 500;
    return (location - this.location).norm <= distance;
  }
}

class _Stations extends Odpts<Station> {
  List<Circle> circles = [];  // list of circle of the place API calls
  List<int> hit = [];   // list of # of stations in each circle

  _Stations() : super('odpt:Station', Odpts.permanentCache, Station());

  _fromJson(final Map<String, dynamic> json) {
    circles = json['odpt:Station.circle']?.map((value) =>
        Circle.fromJson(value))?.toList()?.cast<Circle>() ?? [];
    hit = json['odpt:Station.hit']?.toList()?.cast<int>() ?? [];
    this.fromJson(json);
  }

  // places API with odpt:Station
  Future<List<Station>> getRange(Circle circle) async {
    if (config.waitAPI) {
      await Future.delayed(Duration(seconds: Config.waitAPISeconds));
    }
    await odpt.save();
    if (circle == null) return null;
    Circle circleOrigin = circle;
    if (!(_useCache && (circles.any((item) => circle <= item)))) {
      // cache miss -> get larger area
      circle = Circle(circle.center, max(5000, circle.radius * 1.5));
      logger.info('Cache miss and getting statins in the area of :$circle '
          'at:${DateTime.now()}');
      final String requestUri =
          '${base_uri}places/odpt:Station?'
          'lon=${circle.longitude}&lat=${circle.latitude}'
          '&radius=${circle.radius}'
          '&acl:consumerKey=$apikey_opendata';
      logger.info('Getting: $requestUri at:${DateTime.now()}');
      http.Response response;
      try {
        config.addAPI();
        response = await http.get(requestUri).timeout(Duration(seconds: 10));
      } catch (e) {
        logger.severe(e.toString());
        return null;
      }
      logger.info('Got response at:${DateTime.now()}');
      if (response.statusCode == 429) {
        logger.warning('429: Too Many Requests on place API and wait'
            ' ${Config.waitAPISeconds} seconds.');
        config.waitAPI = true;
        // retry to call API
        await getRange(circleOrigin);
        config.waitAPI = false;
      } else if (response.statusCode == 200) {
        final List<Station> list = [];
        final List<dynamic> decoded = json.decode(response.body);
        for (final item in decoded) {
          Station station = Station();
          list.add(station.fromJson(item));
        }
        if (list.isNotEmpty) {
          logger.info('Succeeded #${list.length} on places API.');
          for (final Station station in list) {
            bases..putIfAbsent(station.owl, () => station);
          }
          logger.info('Added cache #${list.length} of Station.');
          circles.removeWhere((item) => item <= circle);
          circles.add(circle);
          hit.add(list.length);
          logger.info('Revised the record of calling place API.');
//          return list;  // Do not reply all of gotten larger area
        } else {
          logger.info('Succeeded but no content from places API.');
          return [];
        }
      } else {
        logger.severe('Failed on places API'
            ' with code ${response.statusCode}');
        return null;
      }
    }
    // cache hit or got cache
    final List<Station> list = [];
    bases.forEach((String key, Station station) {
      if (station.location != null) {
        if (circleOrigin.has(station.location)) list.add(station);
      }
    });
    logger.config('Hit cache :$circleOrigin #${list.length} in Stations '
        'at:${DateTime.now()}');
    return list;
  }

  // Get Stations at least min
  Future<List<Station>> getRangeAuto(final Location location,
      [final int minRadius = 1000, final int minStations = 1]) async {
    if (location == null) return null;
    const List<double> radiuses = [1000, 1500, 2000, 2500, 3000, 4000, 5000,
      7000, 10000, 15000, 20000, 30000];
    for (double radius in radiuses) {
      if (radius < minRadius) continue;
      List<Station> list = await getRange(Circle(location, radius));
      if (list == null) return null;
      if (list.length >= minStations) return list;
    }
    return [];
  }

  // Get the station where you are now
  Future<List<Station>> getHere(final Location location) async {
    List<Station> list = await getRange(Circle(location, 500));
    if (list?.isNotEmpty ?? false) {
      list.retainWhere((item) => item.isHere(location));
    }
    return list;
  }
}

// rdf:type of odpt:StationTimetable
@immutable
class StationTimetable extends Odpt {
  final String owlOperator;
  final String owlRailway;
  final String owlStation;
  final String owlRailDirection;
  final String owlCalendar;
//  final List<StationTimetableObject> owlStationTimetableObjects;
  final List<TimetableObject> owlTimetableObjects;
  final String owlCandidateTerminalStation;

  StationTimetable() : this._();
  StationTimetable._([Odpt base, this.owlOperator, this.owlRailway,
    this.owlStation, this.owlRailDirection, this.owlCalendar,
    this.owlTimetableObjects, this.owlCandidateTerminalStation])
      : super._clone(base);

  @override
  StationTimetable notExist() => StationTimetable._(super.notExist());
  @override
  StationTimetable fromJson(final Map<String, dynamic> json) {
    if (json == null) return null;
    List<TimetableObject> objects =
    json['odpt:stationTimetableObject']?.map((value) =>
        TimetableObject.fromJsonStation(value, json['owl:sameAs']))?.
    toList()?.cast<TimetableObject>();
    String owlStation = _owlCandidateTerminalStation(objects);
    return StationTimetable._(super.fromJson(json),
        json['odpt:operator'],
        json['odpt:railway'],
        json['odpt:station'],
        json['odpt:railDirection'],
        json['odpt:calendar'],
        objects, owlStation);
  }
  @override
  Map<String, dynamic> toJson() {
    Map<String, dynamic> map = super.toJson();
    map?.addAll({'odpt:operator': owlOperator,
      'odpt:railway' : owlRailway,
      'odpt:station' : owlStation,
      'odpt:railDirection' : owlRailDirection,
      'odpt:calendar' : owlCalendar,
      'odpt:stationTimetableObject': owlTimetableObjects});
    return map;
  }
  @override
  String toString() => '$owlOperator, $owlRailway, $owlStation, '
      '$owlRailDirection, $owlCalendar, $owlTimetableObjects, '
      '$owlCandidateTerminalStation';

  // Just at the same minute
  int index(final Time time) {
    return owlTimetableObjects.indexWhere((item) =>
    time.hm == item.departureTime.hm);
  }
  // 'Next' includes at the same minute
  int getNextDepartureIndexByTime(final Time time) {
    return owlTimetableObjects.indexWhere((item) =>
    time.hm <= item.departureTime.hm);
  }
  // 'Previous' includes at the same minute
  int getPreviousDepartureIndexByTime(final Time time) {
    return owlTimetableObjects.lastIndexWhere((item) =>
    time.hm >= item.departureTime.hm);
  }
  Time getNextDepartureTime(final Time time) {
    int i = getNextDepartureIndexByTime(time);
    if (i < 0) return null;
    return owlTimetableObjects[i].departureTime;
  }
  Time getPreviousDepartureTime(final Time time) {
    int i = getPreviousDepartureIndexByTime(time);
    if (i < 0) return null;
    return owlTimetableObjects[i].departureTime;
  }
  List<int> getNearDepartureIndexesByTime(
      final Time originTime, final Time minTime, final Time maxTime) {
    List<int> result = [];
    Time time = originTime;
    for (int i = getPreviousDepartureIndexByTime(time); i >= 0; i--) {
      time = owlTimetableObjects[i].departureTime;
      if (time < minTime) break;
      result.add(i);
    }
    time = originTime + Time.fromMinutes();
    for (int i = getNextDepartureIndexByTime(time);
        i < owlTimetableObjects.length; i++) {
      time = owlTimetableObjects[i].departureTime;
      if (time > maxTime) break;
      result.add(i);
    }
    result.sort((a, b) =>
        (owlTimetableObjects[a].departureTime.
        compareTo(originTime).abs() -
            (owlTimetableObjects[b].departureTime.
            compareTo(originTime).abs())));
    return result;
  }

  // The most # of destination should be the terminal
  // CAUTION: Tokyu.Toyoko 's terminal 'Motomachichukagai' is not included
  //          in the railway. This function estimates the exactly one.
  String _owlCandidateTerminalStation(List<TimetableObject> objects) {
    Map<String, int> ranking = {};
    for (TimetableObject object in objects) {
      if (object.owlDestinationStations == null) return null;
      for (String owlTerminal in object.owlDestinationStations) {
        ranking..putIfAbsent(owlTerminal, () => 0);
        ranking[owlTerminal] = ranking[owlTerminal] + 1;
      }
    }
    List<String> candidates = [];
    ranking.forEach((key, value) => candidates.add(key));
    candidates.sort((a, b) => ranking[b] - ranking[a]);
    return candidates[0];
  }
}

class _StationTimetables extends Odpts<StationTimetable> {
  _StationTimetables() :
        super('odpt:StationTimetable', Odpts.permanentCache, StationTimetable());
}

// The combined class of
//   rdf:type of odpt:StationTimetableObject
//   rdf:type of odpt:TrainTimetableObject
@immutable
class TimetableObject {
  final String owlCalendar;
  final String owlRailway;
  final String owlRailDirection;
  final String owlTrain;
  final String trainNumber;
  final String owlTrainType;
  final List<String> owlDestinationStations;
  final Time departureTime;
  final String owlDepartureStation;
  final Time arrivalTime;
  final String owlArrivalStation;

  String get owlStation => owlDepartureStation ?? owlArrivalStation;
  Time get time => departureTime ?? arrivalTime;
  String get owlTimetable => odpt._owlCreateTimetable(
      owlStation, owlRailDirection, owlCalendar);
  String get owlOperator => odpt._owlRailwayToOperator(owlRailway);

  TimetableObject._(this.owlCalendar, this.owlRailway, this.owlRailDirection,
      this.owlTrain, this.trainNumber, this.owlTrainType,
      this.owlDestinationStations, this.departureTime, this.owlDepartureStation,
      [this.arrivalTime, this.owlArrivalStation]);
  TimetableObject.setDeparture(TimetableObject object,
      [Time departureTime, String owlDepartureStation]) :
        this._(object.owlCalendar, object.owlRailway, object.owlRailDirection,
          object.owlTrain, object.trainNumber, object.owlTrainType,
          object.owlDestinationStations, departureTime, owlDepartureStation,
          object.arrivalTime, object.owlArrivalStation);
  TimetableObject.setArrival(TimetableObject object,
      [Time arrivalTime, String owlArrivalStation]) :
        this._(object.owlCalendar, object.owlRailway, object.owlRailDirection,
          object.owlTrain, object.trainNumber, object.owlTrainType,
          object.owlDestinationStations, object.departureTime,
          object.owlDepartureStation, arrivalTime, owlArrivalStation);

  TimetableObject.fromJsonStation(final Map<String, dynamic> json,
      String owlTimetable) :
      this._(odpt._owlTimetableToCalendar(owlTimetable),
          odpt._owlTimetableToRailway(owlTimetable),
          odpt._owlTimetableToRailDirection(owlTimetable),
          json['odpt:train'],
          json['odpt:trainNumber'],
          json['odpt:trainType'],
          json['odpt:destinationStation']?.toList()?.cast<String>(),
          Time(json['odpt:departureTime']),
          odpt._owlTimetableToStation(owlTimetable));
  factory TimetableObject.fromJsonTrain(final Map<String, dynamic> json,
      String owlCalendar, String owlRailway, String owlRailDirection,
      String trainNumber, String owlTrainType,
      List<String> owlDestinationStations) {
    assert(owlDestinationStations?.isNotEmpty ?? false);

    String owlDepartureStation = json['odpt:departureStation'];
    String owlArrivalStation = json['odpt:arrivalStation'];
    String owlTimetable = odpt._owlCreateTimetable(
        owlDepartureStation ?? owlArrivalStation,
        owlRailDirection, owlCalendar);
    String owlTrain = odpt._owlTimetableToTrain(owlTimetable, trainNumber);
    return TimetableObject._(
        owlCalendar, owlRailway, owlRailDirection, owlTrain, trainNumber,
        owlTrainType, owlDestinationStations,
        Time(json['odpt:departureTime']),
        json['odpt:departureStation'],
        Time(json['odpt:arraivalTime']),
        json['odpt:arrivalStation']);
  }
  Map<String, dynamic> toJson() => {
    'odpt:train': owlTrain,
    'odpt:trainNumber' : trainNumber,
    'odpt:destinationStation' : owlDestinationStations,
    'odpt:trainType' : owlTrainType,
    'odpt:departureTime' : departureTime?.format('h:m'),
    'odpt:departureStation' : owlDepartureStation,
    'odpt:arrivalTime' : arrivalTime?.format('h:m'),
    'odpt:arrivalStation' : owlArrivalStation,
  };

  @override
  String toString() => '($owlStation, $time, $owlTrainType'
      ', $owlDestinationStations)';

  Future<String> get trainTypeShortTitle =>
      odpt.trainTypes.shortTitle(owlTrainType);
  Future<String> get trainTypeTitle => odpt.trainTypes.title(owlTrainType);
  Future<String> get destinationTitle async {
    if (owlDestinationStations?.isEmpty ?? true) return '';
    String result = '';
    for (String dest in owlDestinationStations) {
      if (result != '') result += '+';
      result += await odpt.stations.title(dest);
    }
    return result;
  }
  Future<String> destinationShortTitle(StationTimetable timetable) async {
    if (owlDestinationStations?.isEmpty ?? true) return '';
    String result = '';
    for (String dest in owlDestinationStations) {
      if (result != '') result += '+';
      if (dest == timetable?.owlCandidateTerminalStation) continue;
      result += String.fromCharCode(
          (await odpt.stations.title(dest)).runes.first);
    }
    return result;
  }
  bool isSimilar(TimetableObject object) {
    // Won't compare with trainNumber
    if (owlTrainType != object.owlTrainType) return false;
    if ((owlDestinationStations?.isEmpty ?? true) &&
        (object.owlDestinationStations?.isEmpty ?? true)) return true;
    if ((owlDestinationStations?.isNotEmpty ?? false) &&
        (object.owlDestinationStations?.isNotEmpty ?? false)) {
      for (String owlStation in owlDestinationStations) {
        if (object.owlDestinationStations.contains(owlStation)) return true;
      }
    }
    return false;
  }

  // Get the StationTimetableObject of  the next station
  // include transit, terminal, and stop.
  Future<TimetableObject> nextStation() async {
    // TODO: consider connecting line
    if ((departureTime == null) || (owlDepartureStation == null)) return null;
    Station station = await odpt.stations.get(owlDepartureStation);
    if (station?.location?.isNotReady ?? true) return null;
    Railway railway = await odpt.railways.get(owlRailway);
    if (railway == null) return null;
    AD ad = railway.ad(owlRailDirection);
    List<String> owlNextStations = railway.owlNexts(owlDepartureStation, ad);
    if (owlNextStations?.isEmpty ?? true) return null;
    // TODO: consider Oedo Line
    String owlNextStation = owlNextStations[0];
    double distance = await railway.distance(
        owlDepartureStation, owlNextStation, ad);
    Time nextTime;
    TimetableObject nextObject = await nextStop();
    if (nextObject == null) {
      nextTime = departureTime + odpt._durationFromDistance(distance);
    } else {
      String owlNextStop = nextObject.owlStation;
      if (owlNextStation == owlNextStop) {
        nextTime = nextObject.time;
      } else {
        double distance2 = await railway.distance(
            owlDepartureStation, owlNextStop, ad);
        nextTime = departureTime +
            (nextObject.time - departureTime) * (distance / distance2);
      }
    }
    return TimetableObject.setDeparture(this, nextTime, owlNextStation);
  }

  // Get the StationTimetableObject of the next stop
  Future<TimetableObject> nextStop() async {
    if (departureTime == null) return null;
    String owlFromStation = owlStation;
    Station fromStation = await odpt.stations.get(owlFromStation);
    if (fromStation?.location?.isNotReady ?? true) return null;
    Railway railway = await odpt.railways.get(owlRailway);
    if (railway == null) return null;
    AD ad = railway.ad(owlRailDirection);
    List<String> owlNextStations = List(10);
    Time duration = Time.zero();
    owlNextStations[0] = owlFromStation;
    // Assume max 9 transit stations
    for (int i = 1; i < 10; i++) {
      owlNextStations[i] = railway.owlNexts(owlNextStations[i-1], ad)[0];
      double distance = await railway.distance(
          owlNextStations[i-1], owlNextStations[i], ad);
      duration = duration + odpt._durationFromDistance(distance);
      Time nextTime = departureTime + duration;
      String owlNextTimetable = odpt._owlCreateTimetable(
          owlNextStations[i], owlRailDirection, owlCalendar);
      if (railway.isTerminal(owlNextStations[i], ad) ||
          (owlDestinationStations?.contains(owlNextStations[i]) ?? false)) {
        // return virtual object
        // Assume all trains stop at the railway terminal.
        // CAUTION Keikyu.AirportRapidLimitedExpress don't stop at that.
        return TimetableObject.setDeparture(TimetableObject.setArrival(
            this, nextTime, owlNextStations[i]));
      }
      StationTimetable nextTimetable = await odpt.stationTimetables.get(
          owlNextTimetable);
      if (nextTimetable == null) return null;
      // Get nearest object with the nextTime and the similar train
      // between minTime and maxTime
      Time minTime = departureTime + duration / 2;
      if (nextTime < minTime + Time.fromMinutes()) {
        nextTime = minTime + Time.fromMinutes();
      }
      Time maxTime = departureTime + duration * 2;
      if (maxTime < nextTime + Time.fromMinutes()) {
        maxTime = nextTime + Time.fromMinutes();
      }
      List<int> indexes = nextTimetable.getNearDepartureIndexesByTime(
          nextTime, minTime, maxTime);
      if (indexes?.isEmpty ?? true) continue;
      nextTime = null;
      for (int index in indexes) {
        TimetableObject object = nextTimetable.owlTimetableObjects[index];
        if (isSimilar(object)) return object;
      }
    }
    return null;
  }

  Future<bool> isValid() async {
    // Check if the parent timetable is expired
    Station station = await odpt.stations.get(owlStation);
    if (station == null) return false;
    return station.isValidTimeTable(owlTimetable);
  }

  Future<bool> isTransit() async {
    // TODO: Handle transit and terminal by checking another timetable
    if (await isTerminal()) return false;
    if (!await isValid()) return false;
    StationTimetable timetable = await odpt.stationTimetables.get(owlTimetable);
    if (timetable == null) return false;
    int index = timetable.index(departureTime);
    if (index < 0) return true;
    return !isSimilar(timetable.owlTimetableObjects[index]);
  }

  Future<bool> isStop() async {
    // TODO: Handle transit and terminal by checking another timetable
    if (await isTerminal()) return true;
    if (!await isValid()) return false;
    StationTimetable timetable = await odpt.stationTimetables.get(owlTimetable);
    if (timetable == null) return false;
    int index = timetable.index(departureTime);
    if (index < 0) return false;
    return isSimilar(timetable.owlTimetableObjects[index]);
  }

  Future<bool> isTerminal() async {
    // Check if hear is the destination
    if (owlDestinationStations?.contains(owlStation) ?? false) return true;
    // Check if hear is the terminal of the railway
    Railway railway = await odpt.railways.get(owlRailway);
    assert(railway != null);
    AD ad = railway.ad(owlRailDirection);
    int index = railway.stationIndex(owlStation, ad);
    return railway.isTerminalIndex(index, ad);
  }

  Future<Train> createVirtualTrain([String owlTrain]) async {
    // create virtual owlTrain
    String trainNumber;
    if (owlTrain == null) {
      trainNumber = odpt._owlCreateVirtualTrainNumber(
          owlTimetable, departureTime.toString());
      owlTrain = odpt._owlTimetableToTrain(owlTimetable, trainNumber);
    } else {
      trainNumber = odpt._owlTrainToTrainNumber(owlTrain);
    }
    // create virtual train
    Odpt base = Odpt._(true, owlTrain);
    return Train._(base, owlOperator, owlRailway, owlRailDirection,
        trainNumber, null, null, owlDestinationStations,
        0, Time.zero()).updateVirtual(owlStation);
  }

  TrainTimetable createVirtualTrainTimetable(Train train) {
    String trainNumber = train.trainNumber;
    String owlTrainTimetable =
    odpt._owlTimetableToTrainTimetable(owlTimetable, trainNumber);
    Odpt base = Odpt._(true, owlTrainTimetable);
    List<String> owlOriginStations = [];
    List<TimetableObject> owlTimetableObjects = [];
    return TrainTimetable._(base, owlOperator, owlRailway, owlRailDirection,
        owlCalendar, trainNumber, owlTrainType, owlOriginStations,
        owlDestinationStations, owlTimetableObjects);
  }
}

// rdf:type of odpt:Train
@immutable
class Train extends Odpt {
  final String owlOperator;
  final String owlRailway;
  final String owlRailDirection;
  final String trainNumber;
  final String owlFromStation;
  final String owlToStation;
  final List<String> owlDestinationStations;
  final int index;
  final Time delay;
  final int carComposition;

  Train() : this._();
  Train._([Odpt base, this.owlOperator, this.owlRailway, this.owlRailDirection,
    this.trainNumber, this.owlFromStation, this.owlToStation,
    this.owlDestinationStations, this.index, this.delay, this.carComposition])
      : super._clone(base);
  Odpt get base => super.clone();

  @override
  String toString() => '$trainNumber from:$owlFromStation -> to:$owlToStation'
      ' 行き先:$owlDestinationStations ($delay遅れ)';
  @override
  Train notExist() => Train._(super.notExist());
  @override
  Train fromJson(final Map<String, dynamic> json) {
    int delay = json['index'] != null ? int.parse(json['index']) : 0;
    if (delay < 60) delay *= 60; // minutes or seconds
    return Train._(
        super.fromJson(json),
        json['odpt:operator'],
        json['odpt:railway'],
        json['odpt:railDirection'],
        json['odpt:trainNumber'],
        json['odpt:fromStation'],
        json['odpt:toStation'],
        json['odpt:destinationStation']?.toList()?.cast<String>(),
        json['index'] != null ? int.parse(json['index']) : null,
        Time.fromSeconds(delay),
        json['carComposition'] != null ?
        int.parse(json['carComposition']) : null
    );
  }
  Train.updateFromTo(Train train, String from, String to) :
      this._(train.base, train.owlOperator, train.owlRailway,
      train.owlRailDirection, train.trainNumber, from, to,
      train.owlDestinationStations, train.index, train.delay,
      train.carComposition);
  Train.updateDelay(Train train, Time delay) :
        this._(train.base, train.owlOperator, train.owlRailway,
          train.owlRailDirection, train.trainNumber, train.owlFromStation,
          train.owlToStation,
          train.owlDestinationStations, train.index, delay,
          train.carComposition);

  Future<Train> updateVirtual(String from) async {
    Railway railway = await odpt.railways.get(owlRailway);
    AD ad = railway?.ad(owlRailDirection);
    List<String> owlToStations = railway?.owlNexts(from, ad);
    String to;
    // owlToStations[1] can be ignored, because Oedo Line has TrainTimetable
    if (owlToStations?.isNotEmpty ?? false) to = owlToStations[0];
    return Train.updateFromTo(this, from, to);
  }
}

class _Trains extends Odpts<Train> {
  _Trains() : super('odpt:Train', Odpts.tempCache, Train());
}

// rdf:type of odpt:TrainInformation
@immutable
class TrainInformation extends Odpt {
  final String owlOperator;
  final String owlRailway;
  final String text;

  TrainInformation() : this._();
  TrainInformation._([Odpt base, this.owlOperator, this.owlRailway, this.text])
      : super._clone(base);

  @override
  TrainInformation notExist() => TrainInformation._(super.notExist());
  @override
  TrainInformation fromJson(final Map<String, dynamic> json) {
    // YokohamaMunicipal Line replies wrong key !!!
    Map<String, dynamic> text = json['odpt:trainInformationText'] ??
        json['odpt:trainInformationStatus'];
      return TrainInformation._(super.fromJson(json),
        json['odpt:operator'],
        json['odpt:railway'],
        text['ja'],
      );}

  String get textEx {
    if (text == null) return '運転状況不明';
    if (text == '平常運転') return '平常運転中';
    if (text.contains('平常通り')) return '平常運転中';
    if (text.contains('平常どおり')) return '平常運転中';
    if (text.contains('以上の遅延はありません')) return '平常運転中';
    if (text.contains('運行情報履歴はありません')) return '平常運転中';
    return text;
  }
}

class _TrainInformations extends Odpts<TrainInformation> {
  _TrainInformations() :
        super('odpt:TrainInformation', Odpts.getAll, TrainInformation());
  // Some operator does not provide information for each railway
  @override
  Future<TrainInformation> get(final String owl) async {
    TrainInformation result = await super.get(owl);
    if (result == null) {
      // Get information for operator itself
      result = await super.get(odpt._owlTrainInformationShort(owl));
    }
    return result;
  }
}

// rdf:type of odpt:TrainTaimtable
@immutable
class TrainTimetable extends Odpt {
  final String owlOperator;
  final String owlRailway;
  final String owlRailDirection;
  final String owlCalendar;
  final String trainNumber;
  final String owlTrainType;
  final List<String> owlOriginStations;
  final List<String> owlDestinationStations;
  final List<TimetableObject> owlTimetableObjects;

  TrainTimetable() : this._();
  TrainTimetable._([Odpt base, this.owlOperator, this.owlRailway,
    this.owlRailDirection, this.owlCalendar, this.trainNumber,
    this.owlTrainType, this.owlOriginStations, this.owlDestinationStations,
    this.owlTimetableObjects])
      : super._clone(base);

  @override
  String toString() => '$owlOperator, $owlRailway, $owlRailDirection,'
      ' $owlCalendar, $trainNumber, $owlTrainType, ($owlOriginStations ->'
      ' $owlDestinationStations), $owlTimetableObjects';
  @override
  TrainTimetable notExist() => TrainTimetable._(super.notExist());
  @override
  TrainTimetable fromJson(final Map<String, dynamic> json) {
    if (json == null) return null;
    String owlRailway = json['odpt:railway'];
    String owlRailDirection = json['odpt:railDirection'];
    String owlCalendar = json['odpt:calendar'];
    String trainNumber = json['odpt:trainNumber'];
    String owlTrainType = json['odpt:trainType'];
    List<String> owlDestinationStations =
        json['odpt:destinationStation']?.toList()?.cast<String>();
    List<TimetableObject> objects =
        json['odpt:trainTimetableObject']?.map((value) =>
        TimetableObject.fromJsonTrain(value, owlCalendar, owlRailway,
            owlRailDirection, trainNumber, owlTrainType,
            owlDestinationStations))?.
        toList()?.cast<TimetableObject>();
    return TrainTimetable._(
      super.fromJson(json),
      json['odpt:operator'], owlRailway, owlRailDirection, owlCalendar,
      trainNumber, owlTrainType,
      json['odpt:originStation']?.toList()?.cast<String>(),
      owlDestinationStations,
      objects,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    Map<String, dynamic> map = super.toJson();
    map?.addAll({'odpt:operator': owlOperator,
      'odpt:railway' : owlRailway,
      'odpt:railDirection' : owlRailDirection,
      'odpt:calendar' : owlCalendar,
      'odpt:trainNumber' : trainNumber,
      'odpt:trainType' : owlTrainType,
      'odpt:originStation' : owlOriginStations,
      'odpt:destinationStation' : owlDestinationStations,
      'odpt:trainTimetableObject' : owlTimetableObjects});
    return map;
  }

  Future<String> get trainTypeTitle => odpt.trainTypes.title(owlTrainType);
  Future<String> get destinationTitle async {
    if (owlDestinationStations?.isEmpty ?? true) return '';
    String result = '';
    for (String dest in owlDestinationStations) {
      if (result != '') result += '+';
      result += await odpt.stations.title(dest);
    }
    return result;
  }
}

class _TrainTimetables extends Odpts<TrainTimetable> {
  _TrainTimetables() :
        super('odpt:TrainTimetable', Odpts.permanentCache, TrainTimetable());
}

// Train composited information class
class TrainEx {
  Train train;
  bool realtime;
  Time expired;
  TrainTimetable trainTimetable; // only stop station
  bool isVirtualTrainTimetable;

  // form & the next 5 stations include transit
  static const int maxLenObjects = 6;
  List<TimetableObject> objects;
  double _rating;
  int get rating => (_rating * 100).toInt(); // percent
  bool get valid => rating >= 50;

  TrainEx() {
    train = null;
    realtime = false;
    expired = Time.min();
    trainTimetable = null;
    isVirtualTrainTimetable = false;
    objects = List(maxLenObjects);
    _rating = 0;
  }

  TrainEx._(this.train, this.realtime, this.expired, this.trainTimetable,
      this.isVirtualTrainTimetable, this.objects, this._rating);

  TimetableObject get from => objects[0];
  set from(TimetableObject x) {objects[0] = x;}
  TimetableObject get to => objects[1];
  set to(TimetableObject x) {objects[1] = x;}

  TrainEx clone() {
    List<TimetableObject> objects = List.from(this.objects);
    return TrainEx._(train, realtime, expired, trainTimetable,
        isVirtualTrainTimetable, objects, _rating);
  }

  // calc delay
  updateDelay(Time time) async {
    Station station = await odpt.stations.get(train.owlFromStation);
    double distance = (station.location - gpsController.gps.location).norm;
    Time delay = Time.nonZero(time - objects[0].departureTime -
        odpt._durationFromDistance(distance));
    train = Train.updateDelay(train, delay);
    // delay <= 1 -> rating:1.0,  delay == 15 -> rating:0.7
    _rating = min((15 - train.delay.minutes) / 14 * 0.3 + 0.7, 1);
  }

  Future<TimetableObject> getPrevious() async {
    List<TimetableObject> objects = trainTimetable?.owlTimetableObjects;
    if (objects.isEmpty ?? true) return null;
    Railway railway = await odpt.railways.get(trainTimetable.owlRailway);
    AD ad = railway.ad(trainTimetable.owlRailDirection);
    List<String> owlTraces = [];
    int index = -1;
    String owlStation = from.owlStation;
    for (;;) {
      owlTraces.add(owlStation);
      index = objects.lastIndexWhere(
              (item) => item.owlStation == owlStation);
      if (index >= 0) break;
      owlStation = railway.owlNexts(owlTraces.last, AD.reversed(ad))[0];
      if (owlStation == null) break;
    }
    if (index < 0) return null;
    if (!isVirtualTrainTimetable) return objects[index];
    if (index < objects.length - 1) return objects[index];
    for (; index < objects.length; index++) {
      await _addNextItemOfVirtualTrainTimetable();
      if (owlTraces.lastIndexWhere(
              (item) => item == objects.last.owlStation) < 0) {
        return objects[index];
      }
    }
    return objects[index - 1];
  }

  Future<TimetableObject> getNext() async {
    List<TimetableObject> objects = trainTimetable?.owlTimetableObjects;
    if (objects.isEmpty ?? true) return null;
    TimetableObject previousObject = await getPrevious();
    int i = objects.indexWhere(
            (item) => item.owlStation == (previousObject?.owlStation ?? ''));
    if (i < 0) return null;
    if (i == objects.length - 1) await _addNextItemOfVirtualTrainTimetable();
    if (i == objects.length - 1) return null;
    return objects[i + 1];
  }

  _addNextItemOfVirtualTrainTimetable() async {
    assert(isVirtualTrainTimetable);
    List<TimetableObject> objects = trainTimetable?.owlTimetableObjects;
    assert(objects?.isNotEmpty ?? false);
    int i = objects.length - 1;
    if (i == maxLenObjects - 1) return;
    TimetableObject nextObject = await objects[i].nextStop();
    if (nextObject != null) objects.add(nextObject);
  }

  @override
  String toString() => valid ? 'Realtime:$realtime, Rating:$_rating,'
      'Train:{$train}, from:$from, to:$to, Timetable:{$trainTimetable}': '';

  create(final GPS gps, final TimetableObject object) async {
    if (object == null) return;
    from = object;
    String owlTrain = from.owlTrain;
    if (owlTrain == null) {
      // create virtual owlTrain
      String trainNumber =
      odpt._owlCreateVirtualTrainNumber(
          object.owlTimetable, object.departureTime.format('Hm'));
      owlTrain = odpt._owlTimetableToTrain(object.owlTimetable, trainNumber);
    } else {
      _rating = 1;
      String trainNumber = odpt._owlTrainToTrainNumber(owlTrain);
      String owlTrainTimetable =
      odpt._owlTimetableToTrainTimetable(object.owlTimetable, trainNumber);
      trainTimetable = await odpt.trainTimetables.get(owlTrainTimetable);
    }
    // create virtual train
    train = await object.createVirtualTrain(owlTrain);
    expired = gps.time + Time.fromMinutes();
    // Create virtual trainTimetable
    if (trainTimetable?.owlTimetableObjects?.isEmpty ?? true) {
      trainTimetable = object.createVirtualTrainTimetable(train);
      isVirtualTrainTimetable = true;
      // Make timeTableObject with from
      trainTimetable.owlTimetableObjects.add(object);
    }
    await updateDelay(gps.time);
    // complete objects
    train = await train?.updateVirtual(object.owlStation);
    assert(objects?.isNotEmpty ?? false);
    for (int i = objects.indexOf(null); (0 <= i) && (i < maxLenObjects); i++) {
      objects[i] = await objects[i - 1]?.nextStation();
    }
    await update(gps, atDeparture);
  }

  // update train, objects, trainTimetables, rating, locTime
  static const int atInterval = 0;
  static const int atArrival = 1;
  static const int atDeparture = 2;
  static const int atTransit = 3;
  update(GPS gps, int at, [int numOfTrains = 0]) async {
    if (!valid) return;
    // Shift owlFromStation & owlToStation in the train class
    if ((at == atArrival) || (at == atTransit)) {
      train = await train?.updateVirtual(to.owlStation);
    }
    // Shift objects
    int i = objects.indexWhere(
            (item) => item?.owlStation == train.owlFromStation);
    if (i < 0) {
      _rating = 0;
      return;
    }
    if (i > 0) {
      int j = 0;
      for (; j < maxLenObjects - i; j++) {
        objects[j] = objects[j + i];
      }
      for (; j < maxLenObjects; j++) {
        objects[j] = await objects[j - 1]?.nextStation();
      }
      // TODO: connect another railway if the last is not the destination.
    }
    // grow trainTimetables
    if (isVirtualTrainTimetable) await _addNextItemOfVirtualTrainTimetable();
    // update delay and rating
    if (at == atArrival) {
      _rating = min(1, _rating + 0.2);
      await updateDelay(gps.time + Time.fromSeconds(30));
    } else if (at == atDeparture) {
      await updateDelay(gps.time);
    }
    // Set current pos
    if ((from == null) || (to == null)) return;
    Station fromStation = await odpt.stations.get(from?.owlStation);
    Station toStation = await odpt.stations.get(to?.owlStation);
    if (fromStation?.location?.isNotReady ?? true) return;
    if (toStation?.location?.isNotReady ?? true) return;
    Location fromLoc = fromStation.location;
    Location toLoc = toStation.location;
    // Set rating by the location if there are multiple candidate trains.
    // distance gap 200m : 1.0 - 1000m : 0.7
    // angle gap (if speed >= 30km/h) 60° : 1.0 - 180° : 0.7
    if (numOfTrains == 1) {
      gpsController.from = LocationTime(fromLoc,
          from.departureTime + train.delay);
      gpsController.to = LocationTime(toLoc,
          to.departureTime + train.delay - Time.fromSeconds(30));
      gpsController.improveAccuracy();
    } else {
      double distance = gps.location.perpendicular(fromLoc, toLoc);
      _rating *= min(800, max(0, 1000 - max(0, distance - gps.accuracy))) /
          800 * 0.3 + 0.7;
      if (gps.speed >= 30) {
        _rating *= (min((gps.speedVector.angle - (toLoc - fromLoc).angle).cos(),
            0.5) + 1) / 1.5 * 0.3 + 0.7;
      }
    }
  }

  eliminate() {
    _rating = 0;
  }
}

class TrainsEx {
  List<TrainEx> trains = [];
  Date date;
  bool stable; // true if registered at a station

  @override
  String toString() => 'Stable:$stable -> trains:$trains';

  TrainsEx([Date date]) :
        trains = [], date = date ??= Date.now(), stable = true;

  // Return new list with sorted by rating and eliminated invalid trains
  // CAUTION: The object of each TrainEx is NOT immutable consciously.
  List<TrainEx> sortAndEliminated() {
    if (trains?.isEmpty ?? true) return trains;
    List<TrainEx> list = List.from(trains);
    list.sort((a, b) => b.rating - a.rating);
    list.retainWhere((item) => item.valid);
    return list;
  }

  int get numValidTrains => sortAndEliminated()?.length ?? 0;

  // Start from high speed (on a train)
  fromHighSpeed(GPS gps, [double searchRadius = 3000]) async {
    stable = false;
    Circle circle = Circle(gps.location, searchRadius);
    List<Station> stations = await odpt.stations.getRange(circle);
    await fromStations(gps, stations);
  }

  // Start from low speed (at a station)
  fromLowSpeed(GPS gps) async {
    stable = true;
    List<Station> stations = await odpt.stations.getHere(gps.location);
    await fromStations(gps, stations);
    // Calibrate rating by the distance with fromStation
    for (TrainEx train in trains) {
      Station station = odpt.stations.bases[train.train.owlFromStation];
      assert(station?.location?.isReady ?? false);
      double distance = (gps.location - station.location).norm - gps.accuracy;
      train._rating *= min(450, max(0, 500 - distance)) / 450 * 0.3 + 0.7;
    }
  }

  // Start from stations list
  fromStations(GPS gps, List<Station> stations) async {
    LocationTime locTime = gps.locTime;
    // Getting the candidates of timetable and timetable object index
    // that departures -15min - +1min from this time
    List<Tuple2<StationTimetable, int>> candidates = [];
    for (Station station in stations) {
      if (!stable) {  // Calibrate the time
        double distance = (locTime.location - station.location).norm;
        locTime = LocationTime.setTime(gps.locTime,
            gps.time -odpt._durationFromDistance(distance));
      }
      for (AD ad in [AD.ascend(), AD.descend()]) {
        if (!stable) {  // skip far railways
          bool far = true;
          List<String> owlNexts = await station.owlNexts(ad);
          if (owlNexts?.isNotEmpty ?? false) {
            for (String owlNext in owlNexts) {
              // Won't call API in order to the quick response
              Station next = odpt.stations.bases[owlNext];
              if (next?.location?.isNotReady ?? true) continue;
              if (gps.location.perpendicular(station.location,
                  next.location) < 500 + gps.accuracy +
                  (station.location - next.location).norm ~/ 2) {
                far = false;
                break;
              }
            }
          }
          if (far) continue;
        }
        List<String> owlTimetables =
            await station.getExValidTimetables(date, ad);
        if (owlTimetables?.isEmpty ?? true) continue;
        for (String owlTimetable in owlTimetables) {
          if (!station.isValidTimeTable(owlTimetable)) continue;
          StationTimetable timetable =
              await odpt.stationTimetables.get(owlTimetable);
          if (timetable == null) continue;
          for(int i = timetable.getPreviousDepartureIndexByTime(
              locTime.time + Time.fromMinutes());(0 <= i) &&
              (i < timetable.owlTimetableObjects.length); i--) {
            if (timetable.owlTimetableObjects[i].departureTime <
                locTime.time - Time.fromMinutes(5)) {
              break;
            }
            // remove similar train
            if (candidates.any((item) => item.item1.owl == timetable.owl &&
                item.item1.owlTimetableObjects[item.item2]?.owlTrainType
                == timetable.owlTimetableObjects[i]?.owlTrainType)) {
              continue;
            }
            candidates.add(Tuple2<StationTimetable, int>(timetable, i));
          }
        }
      }
    }
    // create trains
    trains = [];
    if (candidates.isEmpty) return;
    for (Tuple2<StationTimetable, int> candidate in candidates) {
      TrainEx trainEx = TrainEx();
      await trainEx.create(
          gps, candidate.item1.owlTimetableObjects[candidate.item2]);
      if (trainEx != null) trains.add(trainEx);
    }
  }

  update(GPS gps) {
    if (trains?.isEmpty ?? true) return;
    for (TrainEx trainEx in sortAndEliminated()) {
      trainEx.update(gps, TrainEx.atInterval, numValidTrains);
    }
  }
}