import 'dart:math';

/// The Sendspin time filter: a two-dimensional Kalman filter tracking the server clock minus the local clock (`offset`) and its rate of change (`drift`), all in microseconds. It follows the specification step by step (messaging.md, "Time filter").
class TimeFilter {
  static const _processStdDev = 0.0;
  static const _driftProcessStdDev = 1e-11;
  static const _forgetFactor = 2.0;
  static const _adaptiveCutoff = 3.0;
  static const _minSamples = 100;
  static const _driftSignificanceThreshold = 2.0;
  static const _maxErrorScale = 0.5;

  double offset = 0;
  double drift = 0;
  double _pOO = double.infinity;
  double _pOD = 0;
  double _pDD = 0;
  int lastUpdate = 0;
  int count = 0;
  bool useDrift = false;

  /// Standard deviation of the offset estimate in microseconds.
  double get error => sqrt(_pOO);

  /// Feeds one `server/time` exchange: [t1] client transmitted, [t2] server received, [t3] server transmitted, [t4] client received.
  void addExchange(int t1, int t2, int t3, int t4) =>
      update(measurementOf(t1, t2, t3, t4), maxErrorOf(t1, t2, t3, t4), t4);

  static int measurementOf(int t1, int t2, int t3, int t4) =>
      ((t2 - t1) + (t3 - t4)) ~/ 2;
  static int maxErrorOf(int t1, int t2, int t3, int t4) =>
      ((t4 - t1) - (t3 - t2)) ~/ 2;

  void update(int measurement, int maxError, int timeAdded) {
    if (timeAdded <= lastUpdate || maxError <= 0) return;
    final dt = (timeAdded - lastUpdate).toDouble();
    lastUpdate = timeAdded;
    final r = pow(_maxErrorScale * maxError, 2).toDouble();
    if (count == 0) {
      offset = measurement.toDouble();
      _pOO = r;
      drift = 0;
      count = 1;
      return;
    }
    if (count == 1) {
      drift = (measurement - offset) / dt;
      _pDD = (_pOO + r) / (dt * dt);
      offset = measurement.toDouble();
      _pOO = r;
      count = 2;
      return;
    }
    final offsetP = offset + drift * dt;
    var pOOp =
        _pOO +
        2 * _pOD * dt +
        _pDD * dt * dt +
        _processStdDev * _processStdDev * dt;
    var pODp = _pOD + _pDD * dt;
    var pDDp = _pDD + _driftProcessStdDev * _driftProcessStdDev * dt;
    final y = measurement - offsetP;
    if (count < _minSamples) {
      count++;
    } else if (y.abs() > _adaptiveCutoff * maxError) {
      const f = _forgetFactor * _forgetFactor;
      pOOp *= f;
      pODp *= f;
      pDDp *= f;
    }
    final s = pOOp + r;
    final kO = pOOp / s;
    final kD = pODp / s;
    offset = offsetP + kO * y;
    drift = drift + kD * y;
    _pOO = pOOp - kO * pOOp;
    _pOD = pODp - kD * pOOp;
    _pDD = pDDp - kD * pODp;
    useDrift =
        drift * drift >
        _driftSignificanceThreshold * _driftSignificanceThreshold * _pDD;
  }

  double get _d => useDrift ? drift : 0;

  static int _round(double v) =>
      v.isNegative ? -((-v) + 0.5).floor() : (v + 0.5).floor();

  int serverTime(int clientTime) =>
      clientTime + _round(offset + _d * (clientTime - lastUpdate));

  int clientTime(int serverTime) =>
      _round((serverTime - offset + _d * lastUpdate) / (1 + _d));

  /// Whether enough exchanges have passed to schedule playback: two samples and an offset known to within a millisecond.
  bool get converged => count >= 2 && error < 1000;
}
