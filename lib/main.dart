/*
   UpNext main programs
   Copyright (c) 2019 Tatsuzo Osawa
   All rights reserved. This program and the accompanying materials
   are made available under the terms of the MIT License:
   https://opensource.org/licenses/mit-license.php
*/

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'config_secret.dart';
import 'odpt.dart';
import 'location.dart';
import 'format.dart';

const String app_title ='UpNext';
const String term_of_use =
    '入力操作が一切不要な新感覚フルオートナビです。'
    '東京近郊の電車のみに対応しており、バスには対応していません。\n\n'

    '本アプリでは、利用者の行動は、アプリ内での分析のみに使用し、'
    '東京公共交通オープンデータチャレンジAPI利用許諾規約に明記された統計的利用を除き、'
    '外部には記録しません。'
    'さらに、APIキャッシュ以外のデータはアプリ終了時に破棄されます。\n\n'

    '本アプリは、東京公共交通オープンデータチャレンジのコンテスト実施期間である'
    '2020年3月31日を過ぎると、利用できなくなる場合があります。\n\n'

    '*本アプリケーション等が利用する公共交通データは、'
    '東京公共交通オープンデータチャレンジにおいて提供されるものです。'
    '公共交通事業者により提供されたデータを元にしていますが、'
    '必ずしも正確・完全なものとは限りません。本アプリケーションの表示内容について、'
    '公共交通事業者への直接の問合せは行わないでください。'
    '本アプリケーションに関するお問い合わせは、以下のメールアドレスにお願いします。'
    '\n\n$contact_email\n\n';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: app_title,
      theme: ThemeData(
        brightness: Brightness.dark,
      ),
      home: MyHomePage(title: app_title),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Move move;

  @override
  void initState() {
    super.initState();
    mainLoop();
  }

  mainLoop() async {
    await init();
    await for (GPS gps in gpsController) {
      // Local gps variable will be used only for an event trigger
      logger.info('Handling gps stream: ${move.gps}');
      logger.info('Handling move stream: $move');

      await odpt.save();  // Save cache periodically
      await move.update(this);
      view();

      // Wait 1000 ms for blinking
      await Future.delayed(Duration(milliseconds: 500));
      move.blink();
      view();
    }
  }

  init() async {
    // Setup location
    move = Move();
    await odpt.init();
    Map<String, dynamic> json;
    if (config.isGpsReplay) {
      String fileData = await rootBundle.loadString('assets/json.txt');
      json = jsonDecode(fileData);
    }
    gpsController.init(json);
    await move.update(this);
    view();
  }

  view() {
    setState(() => move.output);
  }

  Future<void> resetMove() => Future.sync(() {
    init();
  });

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    initialIndex: 0,
    child: Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
          title: Text(widget.title),
          bottom: TabBar(
              tabs: <Widget>[
                Tab(icon: Icon(Icons.home,),),
                Tab(icon: Icon(Icons.info,),),
              ]
          )
      ),

      body: TabBarView(
        children: <Widget>[
          (move?.output?.isEmpty ?? true) ? CircularProgressIndicator() :
          RefreshIndicator(
            child: ListView.builder(
              itemCount: move.output.length,
              itemBuilder: (context, int index) => Padding(
                  padding: EdgeInsets.all(8.0),
                  child: move.output[index].listTile(),
              )
            ),
            onRefresh: resetMove,
          ),
          Padding(
            padding: EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Image.asset('assets/icon_ios.png'),
                      ),
                      Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          app_title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(term_of_use),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ListTile View parameter
@immutable
class Tile {
  final Widget _leading;
  final String _title;
  final String _subtitle;
  final Widget _trailing;

  Tile(this._leading, this._title, [this._subtitle = '', this._trailing]);
  Tile changeLeading(final Widget leading) =>
      Tile(leading, _title, _subtitle, _trailing);
  ListTile listTile() {
    Text textTitle = ((_title == null) || (_title == '')) ? null : Text(_title);
    Text textSubtitle =
        ((_subtitle == null) || (_subtitle == '')) ? null : Text(_subtitle);
    return ListTile(leading: _leading,
        title: textTitle, subtitle: textSubtitle, trailing: _trailing);
  }
}

// Management move status and constructing view class
class Move {
  // 0: unknown, 1: walk, 2: station, 3: train
  int _move;

  GPS get gps => gpsController.gps;
  Time _lastChangeMove;
  TrainsEx _trains;
  List<Tile> _output = [];
  int validLength = 0;

  List<Tile> get output => List.from(_output);

  setView(int i, Tile t) {
    assert(_output.length >= i);
    if (_output.length == i) {
      _output.add(t);
    } else {
      _output[i] = t;
    }
  }

  setStateIcon(Icon icon) {
    if (_output?.isEmpty ?? true) return;
    _output[0] = _output[0].changeLeading(icon);
  }

  blink() {
    setStateIcon(Icon(Icons.gps_not_fixed));
  }

  static const int move_unknown = 0;
  static const int move_walk = 1;
  static const int move_station = 2;
  static const int move_train = 3;

  Move([int move = move_unknown, TrainsEx trains]) {
    _trains = trains ??= TrainsEx(gps.date);
    _move = move;
    _stations = [];
  }

  String get moveTitle => _moveTitle[_move];
  static const Map<int, String> _moveTitle = {move_unknown: '確認中',
    move_walk: '徒歩', move_station: '駅', move_train: '電車'};

  @override
  String toString() => '$moveTitle -> $_trains';

  set move(int move) {
    _move = move;
    _lastChangeMove = gps.time;
  }

  update(_MyHomePageState state) async {
    config.resetAPI();
    await _updateState();
    validLength = 1;
    await _updateTrains(state);
    await _updateStations(state);
    _output.removeRange(validLength, _output.length);
  }

  _updateState() async {
    GPS gps0 = gpsController.gpsRaw;
    GPS gps1 = gpsController.gpsLv1;
    bool isGpsRevised = gps0 != gps1;

    switch (_move) {
      case move_unknown:
        // Initialize trainsEx
        _trains = TrainsEx(gps.date);
        // If highSpeed -> train, lowSpeed -> walk
        if (gpsController.isLowSpeed) {
          move = move_walk;
        } else if (gpsController.isHighSpeed) {
          move = move_train;
          _trains.fromHighSpeed(gps);
        }
        break;
      case move_walk:
        // Initialize trainsEx
        _trains = TrainsEx(gps.date);
        // If near the station and changed to highSpeed, or badAccuracy -> train
        if ((gpsController.isHighSpeed) || (gpsController.isBadAccuracy)) {
          List<Station> stations = await odpt.stations.getHere(gps.location);
          if ((stations?.length ?? -1) > 0) {
            move = move_train;
            _trains.fromLowSpeed(gps);
          } else {
            move = move_unknown;
          }
        }
        break;
      case move_station:
        _trains.update(gps);
        // If there is no candidate train -> unknown
        if (_trains.numValidTrains == 0) {
          move = move_unknown;
          break;
        }
        // If keep this move with 2 minutes -> walk
        if ((gps.time - _lastChangeMove).minutes >= 2) {
          move = move_walk;
          break;
        }
        // If changed to highSpeed, or badAccuracy -> train
        if ((gpsController.isHighSpeed) ||
            (gpsController.isBadAccuracy)) {
          for (TrainEx trainEx in _trains.sortAndEliminated()) {
            Station from = await odpt.stations.get(trainEx.from?.owlStation);
            if (from?.isHere(gps.location) ?? false) {
              move = move_train;
              if (await trainEx.from.isStop()) {
                trainEx.update(gps, TrainEx.atDeparture,
                    _trains.numValidTrains);
              } else {
                trainEx.eliminate();
              }
              break;
            }
          }
          if (_move != move_train) move = move_unknown;
        }
        break;
      case move_train:
        _trains.update(gps);
        // If there is no candidate train -> unknown
        if (_trains.numValidTrains == 0) {
          _move = move_unknown;
          break;
        }
        for (TrainEx trainEx in _trains.sortAndEliminated()) {
          Station to = await odpt.stations.get(trainEx.to?.owlStation);
          if (to?.isHere(gps.location) ?? false) {
            // If here is around any station of the train
            if ((gpsController.isLowSpeed) ||
                (isGpsRevised && (gps1.speed < 1))) {
              // and if LowSpeed
              logger.info('Detect a stop station at ${to.title}'
                  ' for ${trainEx.train.owl}');
              if (await trainEx.to.isTerminal()) {
                // and if the station is the terminal -> walk
                move = move_walk;
              } else if (await trainEx.to.isStop()) {
                // and if the station is the stop -> revise trainEx object
                move = move_station;
                trainEx.update(gps, TrainEx.atArrival, _trains.numValidTrains);
              } else {
                trainEx.eliminate();
              }
              break;
            } else {
              // if not LowSpeed and the station is the transit
              if (await trainEx.to.isTransit()) {
                logger.info('Detect a transit station at ${to.title}'
                    ' for ${trainEx.train.owl}');
                trainEx.update(gps, TrainEx.atTransit, _trains.numValidTrains);
              }
            }
          }
        }
        break;
    }

    // Make output by Gps status
    String title = '$moveTitle, 速度:${gps.speedKMH}km/h';
    if (gps.speedKMH > 0) title += ', ${gps.heading.title}';
    String subtitle = '';
    if (gpsController.isGoodAccuracy) {
      subtitle += 'GPS:良好';
    } else if (gpsController.isBadAccuracy) {
      subtitle += 'GPS:悪化中';
    } else {
      subtitle += 'GPS:不良';
    }
    if (gpsController.isHighSpeed) subtitle += '/高速';
    if (gpsController.isLowSpeed) subtitle += '/低速';
    if (isGpsRevised) subtitle += ' -> UpNext補正中';
    if (config.verbose) {
      subtitle += '\n時刻:${gps.time.format('H:m:s')}'
          ', API_calls: ${config.accumulateAPI}回'
          '\nGps0: ${gpsController.configTitle}'
          '\n${gpsController.speedTitle}, ${gpsController.accuracyTitle}'
          '\n-> ±${gps0.accuracy.toInt()}m, ${gps0.speedKMH}km/h';
      if (gps0.speedKMH > 0) subtitle += '(${gps0.heading.title})';
      subtitle += ', ±${gps0.speedAccuracyKMH}km/h';
      if (gps0 != gps1) {
        GPS gap = gps1 - gps0;
        subtitle += '\nGps1: ±${gps1.accuracy.toInt()}m'
            ', ${gps1.speedKMH}km/h';
        if (gps1.speedKMH > 0) subtitle += '(${gps1.heading.title})';
        subtitle += ', ±${gps1.speedAccuracyKMH}km/h'
            '\ngap: ${gap.location.norm.toInt()}m, ${gap.speedKMH}km/h';
        if (gps1.speedKMH > 0) subtitle += '(${gap.heading.degree.toInt()}°)';
      }
    }
    setView(0, Tile(Icon(Icons.gps_fixed), title, subtitle));
  }

  _updateTrains(_MyHomePageState state) async {
    if (config.abort) return;
    if (_trains?.trains?.isEmpty ?? true) return;
    for (TrainEx trainEx in _trains.sortAndEliminated()) {
      Train train = trainEx.train;
      Railway railway =
          await odpt.railways.get(train.owlRailway);
      RailDirection direction =
          await odpt.railDirections.get(train.owlRailDirection);
      String title = '${railway.title}(${direction.title}) '
          '評価:${trainEx.rating}%';
      String subtitle = '';
      TrainInformation info = await odpt.trainInformations.get(
          odpt.owlRailwayToTrainInformation(train.owlRailway));
      if (info != null) subtitle = '${info.textEx}';
      setView(validLength, Tile(Icon(Icons.train), title, subtitle));
      validLength++;
      state.view();
      if (config.abort) continue;

      TimetableObject previous = await trainEx.getPrevious();
      Station station = await odpt.stations.get(previous?.owlStation);
      String destination = await previous?.destinationTitle;
      String trainType = await previous?.trainTypeTitle;
      Time time = previous?.time;
      FormatFunction _hh = () => time?.format('h') ?? '';
      FormatFunction _mm = () => time?.format('m') ?? '';
      FormatFunction _departure = () => '${station?.title ?? '不明'}';
      FormatFunction _destination = () => '$destination';
      FormatFunction _delay = () => '${train.delay.minutes}';
      FormatFunction _trainType = () => '$trainType';
      Format _fmtRailway = Format({
        '{' : 'open',
        '}' : 'close',
        'S': _departure,
        'D': _destination,
        'd': _delay,
        'T': _trainType,
        'hh': _hh,
        'mm': _mm,
      });
      if (subtitle != '') subtitle += '\n';
      subtitle += _fmtRailway.apply('D行: T (遅延d分)');

      TimetableObject next = await trainEx.getNext();
      if (next == null) {
        subtitle += '\n終点到着';
      } else {
        subtitle += _fmtRailway.apply('\nShh:mm発');
        station = await odpt.stations.get(next?.owlStation);
        time = next?.time;
        subtitle += _fmtRailway.apply(' → Shh:mm着');
      }

      if (config.verbose) {
        station = await odpt.stations.get(trainEx.from?.owlStation);
        time = trainEx.from?.departureTime;
        subtitle += _fmtRailway.apply('\nfrom:S{hh:mm}');
        station = await odpt.stations.get(trainEx.to?.owlStation);
        time = trainEx.to?.departureTime;
        subtitle += _fmtRailway.apply('→ to:S{hh:mm}');
        subtitle += ' (遅延${train.delay.seconds}秒)';
      }
      setView(validLength - 1, Tile(Icon(Icons.train), title, subtitle));
      state.view();
    }
  }

  List<Station> _stations;
  List<List<String>> _timetables;
  List<Time> _stationTimes;
  List<int> _stationTypes;
  static const int stationType_unknown = 0;
  static const int stationType_here = 1;
  static const int stationType_stop = 2;
  static const int stationType_transit = 3;
  static const int stationType_connected = 4;
  static const int stationType_walkingTarget = 5;
  Map<int,String> _stationTypeTitle = {
    stationType_unknown: '確認中',
    stationType_here: '停車中',
    stationType_stop: '到着',
    stationType_transit: '通過',
    stationType_connected: '乗換',
    stationType_walkingTarget: '徒歩',
  };
  Map<int,bool> _stationTypeIsViewTime = {
    stationType_unknown: false,
    stationType_here: false,
    stationType_stop: true,
    stationType_transit: true,
    stationType_connected: false,
    stationType_walkingTarget: true,
  };

  _updateStations(_MyHomePageState state) async {
    if (config.abort) return;
    if (gps.isNotReady) return;

    _stations = [];
    _timetables = [];
    _stationTimes = [];
    _stationTypes = [];
    Time delay = Time.zero();
    if (((_move == move_station) || (_move == move_train)) &&
        (_trains.numValidTrains > 0)) {
      // Update stations by the train with the top rating
      TrainEx topTrainEx = _trains.sortAndEliminated()[0];
      delay = topTrainEx.train.delay;
      int index = 0;
      if ((_move == move_train) && (topTrainEx.to != null)) index = 1;
      for (int i = index; i < TrainEx.maxLenObjects; i++) {
        TimetableObject object = topTrainEx.objects[i];
        if (object == null) break;
        Station station = await odpt.stations.get(object.owlStation);
        _stations.add(station);
        _timetables.add([object.owlTimetable]);
        _stationTimes.add(object.departureTime + delay - gps.time);
        if ((_move == move_station) && (i == 0)) {
          _stationTypes.add(stationType_here);
        } else {
          _stationTypes.add(await object.isTransit() ?
              stationType_transit : stationType_stop);
        }
        if ((_stationTypes.last == stationType_stop) &&
            (station.owlConnectingRailway?.isNotEmpty ?? false)) {
          // Setup list of the station of connectedRailways
          for (String owlRailway in station.owlConnectingRailway) {
            String owlConnected =
                odpt.owlCreateConnectingStation(station.owl, owlRailway);
            Station connected = await odpt.stations.get(owlConnected);
            if (connected != null) {
              _stations.add(connected);
              _timetables.add(await connected.getExValidTimetables(gps.date));
              _stationTypes.add(stationType_connected);
              _stationTimes.add(null);
            }
          }
        }
      }
    } else {
      // Update stations by the place
      Circle circle = Circle(gps.location, 1000);
      _stations = await odpt.stations.getRange(circle);
      if (_stations == null) {
        logger.severe('There is no or an error response from ODPT-API.');
        setView(validLength, Tile(Icon(Icons.error),
            'オープンデータAPIにアクセスできないか、エラーが返却されました', ''));
        validLength++;
        return;
      } else if (_stations?.isEmpty ?? true) {
        print('There is no station or no station data around here.');
        setView(validLength, Tile(Icon(Icons.error),
            '近くに駅が見つからないか、近くの駅データがありません', ''));
        validLength++;
        return;
      }
      _stations.sort((a, b) =>
          ((gps.location - a.location).norm -
              (gps.location - b.location).norm).toInt());
      // Make stationTimetables
      for (Station station in _stations) {
        _timetables.add(await station.getExValidTimetables(gps.date));
        if (_move == move_walk) {
          _stationTypes.add(stationType_walkingTarget);
          _stationTimes.add(Time.fromSeconds(
              (station.location - gps.location).norm.toInt())); // Walking 60 m/s
        } else {  // move_unknown
          _stationTypes.add(stationType_unknown);
          _stationTimes.add(null);
        }
      }
    }

    // Make output by stations
    int i = 0;
    for (i = 0; i < _stations.length; i++) {
      Railway railway = await odpt.railways.get(_stations[i].owlRailway);
      String title = '${_stations[i].title}(${railway?.title})';
      title += '\n${(_stations[i].location - gps.location).angle.title}'
          '${(_stations[i].location - gps.location).norm.toInt()}m, ';
      title += _stationTypeTitle[_stationTypes[i]];
      if (_stationTypeIsViewTime[_stationTypes[i]]) {
        if (Time.nonZero(_stationTimes[i]).minutes == 0) {
          title += _move == move_walk ? '到着' : 'まもなく';
        } else {
          title += '${Time.nonZero(_stationTimes[i]).minutes}';
          title += _move == move_walk ? '分' : '分後';
        }
      }
      String subtitle = '';
      String calendarTitle = await _stations[i].getValidCalenderTitle(gps.date);
      if (calendarTitle == null) title += '時刻表データ無し';
      subtitle += '$calendarTitle時刻表';
      if ((_stationTypes[i] == stationType_walkingTarget) ||
          (_stationTypes[i] == stationType_connected)) {
        TrainInformation info = await odpt.trainInformations.get(
            odpt.owlRailwayToTrainInformation(_stations[i].owlRailway));
        if (info != null) subtitle += ', ${info.textEx}';
      }
      setView(validLength, Tile(Icon(Icons.not_listed_location),
          title, subtitle));
      validLength++;
      state.view();
      if (config.abort) continue;

      // Setup view of timetables for each station
      if (_timetables[i]?.isNotEmpty ?? false) {
        for (String owlTimetable in _timetables[i]) {
          if (subtitle != '') subtitle += '\n';
          subtitle += '${await _stations[i].getTimetableTitle(owlTimetable)}: ';
          if (!_stations[i].isValidTimeTable(owlTimetable)) {
            subtitle += '終点';
            continue;
          }
          StationTimetable timetable =
              await odpt.stationTimetables.get(owlTimetable);
          if (timetable == null) {
            subtitle += 'データがありません';
            continue;
          }
          int index = timetable.getNextDepartureIndexByTime(gps.time - delay);
          if (index < 0) {
            subtitle += '運行終了';
            continue;
          }
          List<TimetableObject> objects = timetable.owlTimetableObjects;
          String destination = '';
          String trainType = '';
          Time time;
          FormatFunction _mm = () => time?.format('m');
          FormatFunction _destination = () => '$destination';
          FormatFunction _trainType = () => '$trainType';
          Format _fmtRailway = Format({
            '{' : 'open',
            '}' : 'close',
            'd': _destination,
            't': _trainType,
            'mm': _mm,
          });
          for (int j = 0; j < 5; j++) {
            time = objects[index].departureTime;
            destination = await objects[index].destinationShortTitle(timetable);
            trainType = await objects[index].trainTypeShortTitle;
            String str = _fmtRailway.apply('mm{t}{/d}');
            if (str == '') break;
            if (subtitle != '') subtitle += ' ';
            subtitle += str;
            index++;
            if (index >= objects.length) break;
          }
        }
      }

      // Setup view of connectedRailways
      // if this is the first station of the same connected
      if (_stations.indexWhere((item) => item.title ==
          _stations[i].title) == i) {
        String connectedRailways = '';
        List<String> list = await _stations[i].getConnectingRailwayTitles();
        for (String railway in list) {
          if (connectedRailways != '') connectedRailways += ', ';
          connectedRailways += railway;
        }
        if (connectedRailways != '') {
          if (subtitle != '') subtitle += '\n';
          subtitle += '乗換: $connectedRailways';
        }
      }
      setView(validLength - 1, Tile(Icon(Icons.location_on), title, subtitle));
      state.view();
    }
  }
}
