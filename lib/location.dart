/*
   UpNext Location primitive classes such as Location, Time, and GPS
   Copyright (c) 2019 Tatsuzo Osawa
   All rights reserved. This program and the accompanying materials
   are made available under the terms of the MIT License:
   https://opensource.org/licenses/mit-license.php
*/

import 'dart:async';
import 'dart:math';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'config.dart';

final _GPSController gpsController = _GPSController();

// Angle object, cyclical double number % (2 * pi)
@immutable
class Angle {
  final double rad;

  double get degree => rad * 180 / pi;
  Angle([double rad = 0]) : this.rad = rad % (2 * pi);
  Angle clone() => Angle(rad);
  Angle.clone(Angle a) : rad = a.rad;
  Angle.fromDegree(double degree) : rad = degree * pi / 180;
  Angle.fromLocation(Location loc) : rad = math.atan2(loc.x, loc.y);

  @override
  String toString() => '${degree.toInt()}°';
  @override
  int get hashCode => rad.hashCode;
  @override
  bool operator ==(other) => rad == other.rad;
  Angle operator +(Angle other) => Angle(rad + other.rad);
  Angle operator -(Angle other) => Angle(rad - other.rad);
  double cos() => math.cos(rad);
  double sin() => math.sin(rad);

  String get title => _angleTitle[((degree * 4 + 45) ~/ 90) % 16];
  static const List<String> _angleTitle =
  ['北', '北北東', '北東', '東北東', '東', '東南東', '東南', '南南東',
    '南', '南南西', '南西', '西南西', '西', '西北西', '北西', '北北西'];
}

// Location object with Rectangular coordinate system
// handling latitude and longitude
@immutable
class Location {
  final double x;  // from base point (m) : east +
  final double y;  // from base point (m) : north +
  final double accuracy;  // (m)
  final double ratioX; // ratio between x and longitude: 0.81227 at Tokyo

  double get norm => sqrt(x * x + y * y);
  Angle get angle => Angle.fromLocation(this);
  Location get location => this;

  static const double lat_base = 35.68130;  // base point at Tokyo station
  static const double lon_base = 139.76704;  // base point at Tokyo station
  static const double ratio_base = 0.81227; // base ratio at Tokyo station
  static const double meridian_per_degree = 111132.889; // m / degree
  static const double equator_per_degree = 111319.491; // m / degree
  static const double unlimited_accuracy = 10000000;

  Location([this.x = 0, this.y = 0, this.accuracy = unlimited_accuracy,
    this.ratioX = ratio_base]);
  bool get isNotReady => accuracy >= unlimited_accuracy * 0.01;
  bool get isReady => !isNotReady;
  Location.zero() : this(0, 0, 0);
  Location clone() => Location(x, y, accuracy, ratioX);
  Location.clone(Location loc) : x = loc.x, y = loc.y,
        accuracy = loc.accuracy, ratioX = loc.ratioX;
  Location.fromLatLng(double lat, double lng, [this.accuracy = 0]) :
        x = (lng - lon_base) * equator_per_degree * math.cos(lat * pi / 180),
        y = (lat - lat_base) * meridian_per_degree,
        ratioX = math.cos(lat * pi / 180);
  double get latitude => lat_base + y / meridian_per_degree;
  double get longitude => lon_base + x / (equator_per_degree * ratioX);
  Location.fromGeolocatorPkg(final Position position) :
        this.fromLatLng(position.latitude, position.longitude, position.accuracy);

  Location.fromJson(final Map<String, dynamic> json) :
        this(json['x'], json['y'], json['accuracy'], json['ratioX']);
  Map<String, dynamic> toJson() =>
      {'x': x, 'y': y, 'accuracy': accuracy, 'ratioX': ratioX};

  @override
  String toString() => isReady ? '(${x.toStringAsFixed(1)}, '
      '${y.toStringAsFixed(1)}) '
      '±${accuracy.toStringAsFixed(1)}m' : '(Not Ready)';
  @override
  int get hashCode => (x + y + accuracy).hashCode;
  @override
  bool operator ==(other) => ((x == other.x) && (y == other.y));

  // vector calculation
  Location operator +(other) => Location(x + other.x, y + other.y,
      accuracy + other.accuracy, (ratioX + other.ratioX) / 2);
  //    increase accuracy!
  Location operator -(other) => Location(x - other.x, y - other.y,
      accuracy + other.accuracy, (ratioX + other.ratioX) / 2);
  Location operator *(a) => Location(x * a, y * a, accuracy * a, ratioX);
  Location operator /(a) => Location(x / a, y / a, accuracy / a, ratioX);
  Location abs() => Location(x.abs(), y.abs(), accuracy, ratioX);
  Location max(other) => Location(math.max(x, other.x), math.max(y, other.y),
      math.max(accuracy, other.accuracy), (ratioX + other.ratioX) / 2);
  //    max accuracy !
  Location min(other) => Location(math.min(x, other.x), math.min(y, other.y),
      math.max(accuracy, other.accuracy), (ratioX + other.ratioX) / 2);
  double cos() => angle.cos();
  double sin() => angle.sin();
  Location.fromPolar(double norm, Angle angle, [double accuracy = 0]) :
        this(norm * angle.sin(), norm * angle.cos(), accuracy);
  double dot(Location loc) => x * loc.x + y * loc.y;  // inner product
  factory Location.normalized(Location loc) =>
        loc.norm == 0 ? loc : Location.fromPolar(1, loc.angle, loc.accuracy);
  Location normalize() => Location.normalized(this);

  // Length of perpendicular from the line vertexA to vertexB
  // with considering th perpendicular point is inside of the interval AB
  double perpendicular(Location vertexA, Location vertexB) {
    // Calc the equation of line AB as x = vertexA + t * headingVector;
    Location headingVector = (vertexB - vertexA).normalize();
    if (headingVector.norm == 0) return (this - vertexA).norm;
    double t = (this - vertexA).dot(headingVector);
    // force to inside of the interval AB
    t = math.max(0, math.min((vertexB - vertexA).norm, t));
    Location foot = vertexA + headingVector * t;
    return (this - foot).norm;
  }
}

// Date object handling 3:00-26:00
@immutable
class Date {
  final String _date;
  Date.fromYMD(int year, int month, int day) :
        _date = '${year.toString().padLeft(4, '0')}/'
            '${month.toString().padLeft(2, '0')}/'
            '${day.toString().padLeft(2, '0')}';
  Date(String date) : this.fromYMD(_year(date), _month(date), _day(date));
  Date._(this._date);
  Date clone() => Date._(_date);
  Date.clone(Date date) : _date = date._date;
  factory Date.fromDateTime(DateTime date) {
    DateTime date2 = date.add(-Duration(days: (date.hour < 3 ? 1 : 0)));
    return Date.fromYMD(date2.year, date2.month, date2.day);
  }
  factory Date.now() => Date.fromDateTime(DateTime.now());
  factory Date.fromGeolocatorPkg(Position position) =>
      Date.fromDateTime(DateTime.fromMillisecondsSinceEpoch(
          position.timestamp.millisecondsSinceEpoch));
  @override
  String toString() => _date;
  @override
  int get hashCode => _date.hashCode;
  @override
  bool operator== (other) => _date == other._date;
  bool operator> (Date other) => (_date.compareTo(other._date)) > 0;
  bool operator< (Date other) => (_date.compareTo(other._date)) < 0;

  int get year => _year(_date);
  int get month => _month(_date);
  int get day => _day(_date);
  DateTime get dateTime => DateTime(year, month, day);
  int get weekday => dateTime.weekday;

  static int _year(String date) => int.parse(date.split('/')[0]);
  static int _month(String date) => int.parse(date.split('/')[1]);
  static int _day(String date) => int.parse(date.split('/')[2]);
}

// Time object handling 3:00-26:00
@immutable
class Time {
  final int milliseconds;  // ms

  Time._(int milliseconds) :  this.milliseconds = milliseconds % 86400000;
  Time clone() => Time._(milliseconds);
  Time.clone(Time time) : milliseconds = time.milliseconds;
  factory Time([String time = '00:00']) {
    if (time == null) return null;
    List<String> t = time.split(':');
    int hour = 0;
    int minute = 0;
    int second = 0;
    int milliSecond = 0;
    if (t.length >= 4) milliSecond = int.parse(t[3]);
    if (t.length >= 3) second = int.parse(t[2]);
    if (t.length >= 2) minute = int.parse(t[1]);
    if (t.length >= 1) hour = int.parse(t[0]);
    return Time.fromHMS(hour, minute, second, milliSecond);
  }
  Time.fromDateTime(DateTime date) :
        this.fromHMS(date.hour, date.minute, date.second, date.millisecond);
  Time.fromHMS([int hour = 0, int minute = 0, int second = 0,
    int millisecond = 0]) : this.fromMilliSeconds(hour * 3600000 +
      minute * 60000 + second * 1000 + millisecond);
  Time.fromSeconds(int seconds) : this.fromMilliSeconds(seconds * 1000);
  Time.fromMinutes([int minutes = 1]) : this.fromSeconds(60 * minutes);
  Time.fromMilliSeconds(int ms) : this._(ms);
  Time.fromMillisecondsSinceEpoch(int ms) :
        this.fromDateTime(DateTime.fromMillisecondsSinceEpoch(ms));
  Time.fromGeolocatorPkg(Position position) : this.fromMillisecondsSinceEpoch(
      position.timestamp.millisecondsSinceEpoch);
  factory Time.now() => Time.fromDateTime(DateTime.now());
  factory Time.min() => Time('03:00');
  factory Time.max() => Time('26:59');
  factory Time.zero() => Time('00:00');
  factory Time.nonZero(Time t) => t.sign() < 0 ? Time.zero() : t;

  @override
  String toString() => format('h:m:s.M');
  @override
  int get hashCode => millisecond.hashCode;
  @override
  bool operator ==(other) => this.compareTo(other) == 0;
  int compareTo(Time other) =>
      this.format('H:m:s.M').compareTo(other.format('H:m:s.M'));

  int get hour26 =>  hour < 3 ? hour + 24 : hour;
  int get hour => (milliseconds ~/ 3600000) % 24;
  int get minute => (milliseconds ~/ 60000) % 60;
  int get second => (milliseconds ~/ 1000) % 60;
  int get millisecond => milliseconds % 1000;
  int get seconds => milliseconds ~/ 1000;
  int get minutes => seconds ~/ 60;
  Time get hm => Time.fromHMS(hour, minute);
  bool operator <(other) => this.compareTo(other) < 0;
  bool operator >(other) => this.compareTo(other) > 0;
  bool operator <=(other) => this.compareTo(other) <= 0;
  bool operator >=(other) => this.compareTo(other) >= 0;
  Time operator +(other) => Time._(this.milliseconds + other.milliseconds);
  Time operator -(other) => Time._(this.milliseconds - other.milliseconds);
  Time operator *(a) => Time._((this.milliseconds * a).toInt());
  Time operator /(a) => Time._(this.milliseconds ~/ a);
  int sign() => milliseconds > 43200000 ? -1 : ((milliseconds == 0) ? 0 : 1);

  String format(String fmt) {
    if (fmt == null) return null;
    String result = '';
    for (int char in fmt.runes) {
      switch (String.fromCharCode(char)) {
        case 'H':
          result += '${_pad2(hour26)}';
          break;
        case 'h':
          result += '${_pad2(hour)}';
          break;
        case 'm':
          result += '${_pad2(minute)}';
          break;
        case 's':
          result += '${_pad2(second)}';
          break;
        case 'M':
          result += '${_pad3(millisecond)}';
          break;
        default:
          result += String.fromCharCode(char);
          break;
      }
    }
    return result;
  }
  String _pad2(int x) => x.toString().padLeft(2, '0');
  String _pad3(int x) => x.toString().padLeft(3, '0');
}

@immutable
class LocationTime extends Location {
  final Time time;
  Location get location => super.clone();
  double get x => super.x;
  double get y => super.y;
  double get norm => super.norm;
  Angle get angle => super.angle;
  bool get isNotReady => super.isNotReady;
  bool get isReady => super.isReady;

  LocationTime(Location location, this.time) : super.clone(location);
  LocationTime.fromJson(final Map<String, dynamic> json) :
        this(Location.fromJson(json['location']),
          Time.fromMilliSeconds(json['time']));
  Map<String, dynamic> toJson() => {
    'location': location.toJson(), 'time': time.milliseconds,
  };

  LocationTime.fromGeolocatorPkg(Position position) :
        this(Location.fromGeolocatorPkg(position),
          Time.fromGeolocatorPkg(position));
  LocationTime.setTime(LocationTime locTime, Time time) :
        this(locTime.location, time);
  LocationTime setTime(Time time) => LocationTime.setTime(this, time);
  LocationTime.timeNormalized(LocationTime locTime) :
        this(locTime.time.milliseconds == 0 ? Location() :
      locTime.location * 1000 / locTime.time.milliseconds,
          Time.fromSeconds(1));
  LocationTime timeNormalize() => LocationTime.timeNormalized(this);
  factory LocationTime.mean(LocationTime from, LocationTime to, Time time) =>
      from + (to - from).timeNormalize() * (time - from.time).seconds;

  @override
  int get hashCode => location.hashCode + time.hashCode;
  @override
  bool operator ==(other) =>
      (location == other.location) && (time == other.time);
  @override
  LocationTime operator +(other) => LocationTime(
      location + other.location, time + other.time);
  @override
  LocationTime operator -(other) => LocationTime(
      location - other.location, time - other.time);
  @override
  LocationTime operator *(a) => LocationTime(location * a, time * a);
  @override
  LocationTime operator /(a) => LocationTime(location / a, time / a);
  @override
  toString() => '${super.toString()} at $time';

  // speed calculation
  Location toSpeedVector() => LocationTime.timeNormalized(this).location;//(m/s)
  LocationTime.fromSpeedVector(Location speed) :
        this(speed, Time.fromSeconds(1));
  double get speed => toSpeedVector().norm; // (m/s)
  int get speedKMH => (speed * 3.6).toInt(); // (km/h)
  factory LocationTime.move(LocationTime from, Location speed, Time time) =>
      from + LocationTime.fromSpeedVector(speed) * (time - from.time).seconds;
  LocationTime move(Location speed, Time time) =>
      LocationTime.move(this, speed, time);
}

// Circle area
@immutable
class Circle extends Location {
  final double radius;
  Location get center => super.clone();
  double get x => super.x;
  double get y => super.y;
  Circle(Location center, this.radius) : super.clone(center);
  Circle.fromJson(final Map<String, dynamic> json) :
        this(Location.fromJson(json['center']), json['radius']);
  @override
  Map<String, dynamic> toJson() => {
    'center': center.toJson(), 'radius': radius,
  };

  @override
  toString() => '$center radius:$radius';
  @override
  int get hashCode => super.hashCode + radius.hashCode;
  @override
  bool operator ==(other) => ((center == other.center) &&
      (radius == other.radius));
  bool operator> (other) =>
      (radius > other.radius + (center - other.center).norm);
  bool operator< (other) => (other > this);
  bool operator>= (other) => (this > other) || (this == other);
  bool operator<= (other) => (this < other) || (this == other);
  bool has(Location location) => (center - location).norm <= radius;
}

// GPS class
@immutable
class GPS {
  final LocationTime locTime;
  final Location speedVector;  // (m/s)
  final Date date;

  Location get location => locTime.location;
  Time get time => locTime.time;
  bool get isNotReady => locTime.isNotReady;
  bool get isReady => locTime.isReady;
  double get accuracy => location.accuracy;
  double get speed => speedVector.norm;
  int get speedKMH => (speed * 3.6).toInt();
  Angle get heading => speedVector.angle;
  double get speedAccuracy => speedVector.accuracy;
  int get speedAccuracyKMH => (speedAccuracy * 3.6).toInt();

  GPS([LocationTime locTime, Location speedVector, Date date]) :
        this.locTime = locTime ??= LocationTime(Location(), Time.now()),
        this.speedVector = speedVector ??= Location(),
        this.date = date ??= Date.now();

  GPS.fromJson(final Map<String, dynamic> json) : this(
      LocationTime.fromJson(json['locTime']),
      Location.fromJson(json['speedVector']),
      Date(json['date'])
  );
  Map<String, dynamic> toJson() =>
      {
        'locTime': locTime.toJson(),
        'speedVector': speedVector.toJson(),
        'date': date.toString(),
      };

  GPS.fromGeolocatorPkg(Position position) :
        this(LocationTime.fromGeolocatorPkg(position),
          Location.fromPolar(position.speed, Angle.fromDegree(position.heading),
              position.speedAccuracy), Date.fromGeolocatorPkg(position));
  GPS.setTime(GPS gps, Time time) :
        this(LocationTime(gps.location, time), gps.speedVector, gps.date);
  GPS setTime(Time time) => GPS.setTime(this, time);
  GPS setDate(Date date) => GPS(locTime, speedVector, date);

  @override
  String toString() => '$locTime, ${speedKMH}km/h(${heading.title})';
  @override
  int get hashCode => locTime.hashCode + speedVector.hashCode + date.hashCode;
  @override
  bool operator ==(other) => ((locTime == other.locTime) &&
      (speedVector == other.speedVector) && (date == other.date));
  GPS operator +(other) => GPS(
      locTime + other.locTime, speedVector + other.speedVector, date);
  GPS operator -(other) => GPS(
      locTime - other.locTime, speedVector - other.speedVector, date);
}

class _GPSController extends Stream<GPS> {
  final StreamController<GPS> _controller;
  Time _startTime, _startTimeReal;
  Timer _timer;
  bool _doGeolocatorLoop = false;

  GPS _gpsRaw = GPS();
  GPS gpsLv1 = GPS();  // Level1 adjusted
  Geolocator geolocator = Geolocator();
  List<GPS> gpsRecords = [];
  int _indexGpsRecord = 0;

  _GPSController() : _controller = StreamController<GPS>();

  StreamSubscription<GPS> listen(onChanged(GPS data),
      { Function onError, onDone(), bool cancelOnError }) {
    return _controller.stream.listen(onChanged);
  }

  onChanged(GPS gps) {
    logger.info('OnChanged: $gps');
    _controller.add(gps);
  }

  onDone() {}

  Time get startTime => _startTime;
  Time now() => Time.now() - _startTimeReal + _startTime;
  int get indexGpsRecord => _indexGpsRecord;
  GPS get gps => gpsLv1;
  GPS get gpsRaw => _gpsRaw;
  GPS get previousGpsRaw {
    if ((gpsRecords?.isEmpty ?? true) || (gps?.isNotReady ?? true)) return null;
    int i = gpsRecords.lastIndexWhere((item) => item.time < gps.time);
    if (i < 0) return null;
    return gpsRecords[i];
  }
  GPS get previous2GpsRaw {
    if ((gpsRecords.isEmpty ?? true) || (previousGpsRaw == null)) return null;
    int i = gpsRecords.lastIndexWhere(
            (item) => item.time < previousGpsRaw.time);
    if (i < 0) return null;
    return gpsRecords[i];
  }
  bool get isHighSpeed =>  _gpsRaw.isReady && (_gpsRaw.speedKMH >= 15)
      && (previousGpsRaw != null) && (previousGpsRaw.speedKMH > 10) &&
      ((_gpsRaw.heading - previousGpsRaw.heading).cos() > 0.5);
  bool get isLowSpeed => _gpsRaw.isReady && (_gpsRaw.speedKMH <= 10) &&
      (previousGpsRaw != null) && (previousGpsRaw.speedKMH <= 10);
  bool get isUnknownSpeed => !isHighSpeed && !isLowSpeed;
  bool get isBadAccuracy => _gpsRaw.isReady &&
      (previousGpsRaw != null) && (previous2GpsRaw != null) &&
      ((gpsRaw.accuracy > previousGpsRaw.accuracy * 1.5) ||
      (gpsRaw.accuracy > previous2GpsRaw.accuracy * 1.5)) &&
      !isGoodAccuracy;
  bool get isGoodAccuracy =>
      _gpsRaw.isReady && (gpsRaw.accuracy < 50);
  String get configTitle {
    if (config.isGpsRealtime) {
      return 'Realtime';
    } else if (config.isGpsReplay) {
      return 'Replay';
    } else {
      return 'Pseodo';
    }
  }
  String get speedTitle {
    if (isHighSpeed) {
      return 'High speed';
    } else if (isLowSpeed) {
      return 'Low speed';
    } else {
      return 'Unknown speed';
    }
  }
  String get accuracyTitle {
    if (isBadAccuracy) {
      return 'Bad accuracy';
    } else if (isGoodAccuracy) {
      return 'Good accuracy';
    } else {
      return 'Mid accuracy';
    }
  }

  static GPS _gpsLast = GPS().setTime(Time.min());
  bool isGpsUpdated() {
    if (_gpsRaw.isNotReady) return false;
    if (_gpsRaw == _gpsLast) {
      logger.info('GPS was not updated.');
      return false;
    }
    if (_gpsRaw.time < _gpsLast.time + Time.fromMilliSeconds(500)) {
      // Avoid a large package of GPS revision
      // maybe this app had been in busy or in background for a long time
      logger.info('GPS was updated, but too frequectly.');
      return false;
    }
    _gpsLast = _gpsRaw;
    logger.info('GPS was updated.');
    return true;
  }

  // Initialize real GPS
  // It cannot be in the constructor due to include async process
  init([final Map<String, dynamic> json]) async {
    if (_timer != null) _timer.cancel();
    _startTimeReal = Time.now();
    _gpsRaw = GPS();
    gpsLv1 = GPS();  // Level1 adjusted
    gpsRecords.clear();
    if (config.isGpsRealtime) {
      _startTime = _startTimeReal;
    } else if (config.isGpsReplay) {
      gpsRecords = json['gps']?.map((value) =>
          GPS.fromJson(value))?.toList()?.cast<GPS>();
      _startTime = Time.fromMilliSeconds(json['startTime']);
    } else {
      _startTime = _pseudoGps.first.time;
    }
    _indexGpsRecord = 0;
    _startAsyncEventLoop();
  }

  _startAsyncEventLoop() async {
    _timer = Timer.periodic(Duration(milliseconds: 1000), _onTimer);
    if (config.isGpsRealtime) {  // Realtime mode
      if (_doGeolocatorLoop) return;  // already doing loop
      LocationOptions locationOptions = LocationOptions(
          accuracy: LocationAccuracy.high, distanceFilter: 10);
      _doGeolocatorLoop = true;
      await for (Position position in
      geolocator.getPositionStream(locationOptions)) {
        if (!config.isGpsRealtime) {  // detect gps mode changed and exit
          _doGeolocatorLoop = false;
          return;
        }
        if (_gpsRaw.time <= Time.fromGeolocatorPkg(position)) {
          _gpsRaw = GPS.fromGeolocatorPkg(position);
          if (gpsRecords.isEmpty || gpsRecords.last != _gpsRaw) {
            improveAccuracy();
          }
        } else {
          logger.warning('Realtime GPS was duplicated! Skip this:'
              '${Time.fromGeolocatorPkg(position)} , before:${_gpsRaw.time}');
          continue;
        }
      }
    }
  }

  _onTimer(Timer timer) async {
    if (config.isGpsRealtime) { // Realtime mode
      if (_gpsRaw.isNotReady || (_gpsRaw.time + Time.fromSeconds(3) < now())) {
        Position position;
        try {
          position = await geolocator.getCurrentPosition();
        } catch (e) {
          logger.severe(e.toString());
          return;
        }
        if (_gpsRaw.time <= Time.fromGeolocatorPkg(position)) {
          _gpsRaw = GPS.fromGeolocatorPkg(position);
        } else {
          logger.warning('Realtime GPS was duplicated! Skip this:'
              '${Time.fromGeolocatorPkg(position)} , before:${_gpsRaw.time}');
        }
      }
    } else if (config.isGpsReplay) { // Replay mode
      int newIndexGpsRecord =
      gpsRecords.lastIndexWhere((item) => item.time <= now());
      if (newIndexGpsRecord >= 0) {
        while (newIndexGpsRecord > _indexGpsRecord) {
          _gpsRaw = gpsRecords[_indexGpsRecord];
          _indexGpsRecord++;
          improveAccuracy();
        }
        _gpsRaw = gpsRecords[newIndexGpsRecord];
        if (config.isTimeReal) {
          _gpsRaw = _gpsRaw.setTime(_gpsRaw.time - _startTime + _startTimeReal);
        }
        _indexGpsRecord = newIndexGpsRecord;
      }
    } else if (config.isGpsPseudo){  // Pseudo GPS mode
      int i = _pseudoGps.indexWhere((item) => now() < item.time);
      Location location;
      if (i == 0) {
        location = _pseudoGps.first.location;
      } else if (i == -1) {
        location = _pseudoGps.last.location;
      } else {
        location = LocationTime.mean(
            _pseudoGps[i - 1], _pseudoGps[i], now()).location;
      }
      LocationTime locTime = LocationTime(location, now());
      _gpsRaw = GPS(locTime, (locTime - _gpsRaw.locTime).toSpeedVector(),
          _gpsRaw.date);
      if (config.isTimeReal) {
        _gpsRaw = _gpsRaw.setTime(_gpsRaw.time - _startTime + _startTimeReal);
      }
    }
    improveAccuracy();
  }

  // Calc emulated gps between from & to at the time,
  // with considering a mount of acceleration & breaking
  static Time accelerationDuration = Time.fromSeconds(30);
  static Time breakingDuration = Time.fromSeconds(20);
  LocationTime from;
  LocationTime to;
  improveAccuracy() {
    logger.info('GPS sensed as: $gpsRaw');
    if (!isGpsUpdated()) return;
    if (!config.isGpsReplay) {
      gpsRecords.add(_gpsRaw);
      _indexGpsRecord++;
    }
    if (gpsLv1.isNotReady || isGoodAccuracy || from == null || to == null) {
      from = null;
      to = null;
      gpsLv1 = _gpsRaw;
    } else {
      Time time = _gpsRaw.time;
      if (time < from.time) time = from.time;
      if (time > to.time) time = to.time;
      Time constantDuration =
          to.time - from.time - accelerationDuration - breakingDuration;
      constantDuration = Time.nonZero(constantDuration);
      Time beginConstantTime = from.time +
          (to.time - from.time - constantDuration) *
              accelerationDuration.seconds /
              (accelerationDuration + breakingDuration).seconds;
      Time endConstantTime = to.time -
          (to.time - from.time - constantDuration) * breakingDuration.seconds /
          (accelerationDuration + breakingDuration).seconds;
      double topSpeed = (to.location - from.location).norm /
          (constantDuration + (to.time - from.time - constantDuration) /
              2).seconds;   // m/s
      Angle angle = (to - from).angle;
      LocationTime locTime;
      Location speedVector;
      if (time < beginConstantTime) {  // within acceleration
        locTime = LocationTime(
            from.location + (to - from).normalize() * topSpeed *
                (time - from.time).seconds * (time - from.time).seconds /
                accelerationDuration.seconds / 2, time);
        speedVector = Location.fromPolar(topSpeed * (time - from.time).seconds /
            accelerationDuration.seconds, angle);
      } else if (time > endConstantTime) { // within breaking
        locTime = LocationTime(
            to.location + (from - to).normalize() * topSpeed *
                (to.time - time).seconds * (to.time - time).seconds /
                breakingDuration.seconds / 2, time);
        speedVector = Location.fromPolar(topSpeed * (to.time - time).seconds /
            breakingDuration.seconds, angle);
      } else {  // with topSpeed
        LocationTime locTime1 = LocationTime(
            from.location + (to - from).normalize() * topSpeed *
                accelerationDuration.seconds / 2, beginConstantTime);
        LocationTime locTime2 = LocationTime(
            to.location + (from - to).normalize() * topSpeed *
                breakingDuration.seconds / 2, endConstantTime);
        speedVector = Location.fromPolar(topSpeed, angle);
        locTime = LocationTime.mean(locTime1, locTime2, time);
      }
      gpsLv1 = GPS(locTime, speedVector, _gpsRaw.date);
    }
    onChanged(gpsLv1);
  }

  static List<LocationTime> _pseudoGps = [
/*
    // JR-East.KeihinTohoki
    LocationTime(Location.fromLatLng(35.562499, 139.715926), Time('10:00:00')),  // Kamata
    LocationTime(Location.fromLatLng(35.562499, 139.715926), Time('10:00:11')),
    LocationTime(Location.fromLatLng(35.541644, 139.707153), Time('10:00:30')),
    LocationTime(Location.fromLatLng(35.531656, 139.697235), Time('10:00:50')),  // Kawasaki
*/
/*
    // Toyoko Limited Express Holiday
    LocationTime(Location.fromLatLng(35.575929, 139.659769), Time('10:11:50')),  // Musashi-Kosugi
    LocationTime(Location.fromLatLng(35.575929, 139.659769), Time('10:12:00')),
    LocationTime(Location.fromLatLng(35.589896, 139.668855), Time('10:14:00')),
    LocationTime(Location.fromLatLng(35.607347, 139.668512), Time('10:16:00')),  // Jiyugaoka
    LocationTime(Location.fromLatLng(35.607347, 139.668512), Time('10:16:30')),
    LocationTime(Location.fromLatLng(35.644388, 139.699105), Time('10:21:00')),  // Nakameguro
    LocationTime(Location.fromLatLng(35.644388, 139.699105), Time('10:21:30')),
    LocationTime(Location.fromLatLng(35.653712, 139.707123), Time('10:23:30')),
    LocationTime(Location.fromLatLng(35.659567, 139.702411), Time('10:25:00')),  // Shibuya
    LocationTime(Location.fromLatLng(35.659567, 139.702411), Time('10:26:00')),
    LocationTime(Location.fromLatLng(35.663956, 139.702174), Time('10:26:30')),
    LocationTime(Location.fromLatLng(35.668482, 139.705369), Time('10:27:00')),  // MeijiJinguMae
    LocationTime(Location.fromLatLng(35.668482, 139.705369), Time('10:28:00')),
    LocationTime(Location.fromLatLng(35.672260, 139.708137), Time('10:29:00')),
    LocationTime(Location.fromLatLng(35.687820, 139.702820), Time('10:30:00')),
    LocationTime(Location.fromLatLng(35.690870, 139.704874), Time('10:31:00')),  // ShinjukuSanchome
    LocationTime(Location.fromLatLng(35.690870, 139.704874), Time('10:32:00')),
    LocationTime(Location.fromLatLng(35.724063, 139.717291), Time('10:37:00')),
    LocationTime(Location.fromLatLng(35.729479, 139.710668), Time('10:38:00')),  // Ikebukuro
*/
  // Toei Oedo Holiday
    LocationTime(Location.fromLatLng(35.683415, 139.701595), Time('07:41:45')),  // Yoyogi
    LocationTime(Location.fromLatLng(35.683415, 139.701595), Time('07:42:00')),  //
    LocationTime(Location.fromLatLng(35.688652, 139.698826), Time('07:43:00')),  // Shinjuku
    LocationTime(Location.fromLatLng(35.688652, 139.698826), Time('07:43:30')),  //
    LocationTime(Location.fromLatLng(35.691039, 139.698246), Time('07:44:15')),  //
    LocationTime(Location.fromLatLng(35.690595, 139.692646), Time('07:45:00')),  // Tochomae
    LocationTime(Location.fromLatLng(35.690595, 139.692646), Time('07:46:00')),  //
    LocationTime(Location.fromLatLng(35.689854, 139.684374), Time('07:47:00')),  // NishiShinjukuGochome
    LocationTime(Location.fromLatLng(35.689854, 139.684374), Time('07:48:00')),  //
    LocationTime(Location.fromLatLng(35.689418, 139.681917), Time('07:48:30')),  //
    LocationTime(Location.fromLatLng(35.697530, 139.682883), Time('07:50:00')),  // NakanoSakaue
  ];
}
