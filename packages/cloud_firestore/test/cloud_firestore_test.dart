// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('$Firestore', () {
    const MethodChannel channel = const MethodChannel(
      'plugins.flutter.io/cloud_firestore',
    );

    int mockHandleId = 0;
    final Firestore firestore = Firestore.instance;
    final List<MethodCall> log = <MethodCall>[];
    final CollectionReference collectionReference = firestore.collection('foo');
    final Transaction transaction = new Transaction(0);
    const Map<String, dynamic> kMockDocumentSnapshotData =
        const <String, dynamic>{'1': 2};

    setUp(() async {
      mockHandleId = 0;
      channel.setMockMethodCallHandler((MethodCall methodCall) async {
        log.add(methodCall);
        switch (methodCall.method) {
          case 'Query#addSnapshotListener':
            final int handle = mockHandleId++;
            BinaryMessages.handlePlatformMessage(
              channel.name,
              channel.codec.encodeMethodCall(
                new MethodCall('QuerySnapshot', <String, dynamic>{
                  'handle': handle,
                  'paths': <String>["${methodCall.arguments['path']}/0"],
                  'documents': <dynamic>[kMockDocumentSnapshotData],
                  'documentChanges': <dynamic>[
                    <String, dynamic>{
                      'oldIndex': -1,
                      'newIndex': 0,
                      'type': 'DocumentChangeType.added',
                      'document': kMockDocumentSnapshotData,
                    },
                  ],
                }),
              ),
              (_) {},
            );
            return handle;
          case 'Query#addDocumentListener':
            final int handle = mockHandleId++;
            BinaryMessages.handlePlatformMessage(
              channel.name,
              channel.codec.encodeMethodCall(
                new MethodCall('DocumentSnapshot', <String, dynamic>{
                  'handle': handle,
                  'path': methodCall.arguments['path'],
                  'data': kMockDocumentSnapshotData,
                }),
              ),
              (_) {},
            );
            return handle;
          case 'Query#getDocuments':
            return <String, dynamic>{
              'paths': <String>["${methodCall.arguments['path']}/0"],
              'documents': <dynamic>[kMockDocumentSnapshotData],
              'documentChanges': <dynamic>[
                <String, dynamic>{
                  'oldIndex': -1,
                  'newIndex': 0,
                  'type': 'DocumentChangeType.added',
                  'document': kMockDocumentSnapshotData,
                },
              ],
            };
          case 'DocumentReference#setData':
            return true;
          case 'DocumentReference#get':
            if (methodCall.arguments['path'] == 'foo/bar') {
              return <String, dynamic>{
                'path': 'foo/bar',
                'data': <String, dynamic>{'key1': 'val1'}
              };
            } else if (methodCall.arguments['path'] == 'foo/notExists') {
              return <String, dynamic>{'path': 'foo/notExists', 'data': null};
            }
            throw new PlatformException(code: 'UNKNOWN_PATH');
          case 'Firestore#runTransaction':
            return <String, dynamic>{'1': 3};
          case 'Transaction#get':
            return <String, dynamic>{
              'path': 'foo/bar',
              'data': <String, dynamic>{'key1': 'val1'}
            };
          case 'Transaction#set':
            return null;
          case 'Transaction#update':
            return null;
          case 'Transaction#delete':
            return null;
          default:
            return null;
        }
      });
      log.clear();
    });

    group('Transaction', () {
      test('runTransaction', () async {
        final Map<String, dynamic> result = await firestore.runTransaction(
            (Transaction tx) async {},
            timeout: new Duration(seconds: 3));

        expect(log, <Matcher>[
          isMethodCall('Firestore#runTransaction', arguments: <String, dynamic>{
            'transactionId': 0,
            'transactionTimeout': 3000
          }),
        ]);
        expect(result, equals(<String, dynamic>{'1': 3}));
      });

      test('get', () async {
        final DocumentReference documentReference =
            Firestore.instance.document('foo/bar');
        await transaction.get(documentReference);
        expect(log, <Matcher>[
          isMethodCall('Transaction#get', arguments: <String, dynamic>{
            'transactionId': 0,
            'path': documentReference.path
          })
        ]);
      });

      test('delete', () async {
        final DocumentReference documentReference =
            Firestore.instance.document('foo/bar');
        await transaction.delete(documentReference);
        expect(log, <Matcher>[
          isMethodCall('Transaction#delete', arguments: <String, dynamic>{
            'transactionId': 0,
            'path': documentReference.path
          })
        ]);
      });

      test('update', () async {
        final DocumentReference documentReference =
            Firestore.instance.document('foo/bar');
        final DocumentSnapshot documentSnapshot = await documentReference.get();
        final Map<String, dynamic> data = documentSnapshot.data;
        data['key2'] = 'val2';
        await transaction.set(documentReference, data);
        expect(log, <Matcher>[
          isMethodCall('DocumentReference#get',
              arguments: <String, dynamic>{'path': 'foo/bar'}),
          isMethodCall('Transaction#set', arguments: <String, dynamic>{
            'transactionId': 0,
            'path': documentReference.path,
            'data': <String, dynamic>{'key1': 'val1', 'key2': 'val2'}
          })
        ]);
      });

      test('set', () async {
        final DocumentReference documentReference =
            Firestore.instance.document('foo/bar');
        final DocumentSnapshot documentSnapshot = await documentReference.get();
        final Map<String, dynamic> data = documentSnapshot.data;
        data['key2'] = 'val2';
        await transaction.set(documentReference, data);
        expect(log, <Matcher>[
          isMethodCall('DocumentReference#get',
              arguments: <String, dynamic>{'path': 'foo/bar'}),
          isMethodCall('Transaction#set', arguments: <String, dynamic>{
            'transactionId': 0,
            'path': documentReference.path,
            'data': <String, dynamic>{'key1': 'val1', 'key2': 'val2'}
          })
        ]);
      });
    });

    group('CollectionsReference', () {
      test('listen', () async {
        final QuerySnapshot snapshot =
            await collectionReference.snapshots.first;
        final DocumentSnapshot document = snapshot.documents[0];
        expect(document.documentID, equals('0'));
        expect(document.reference.path, equals('foo/0'));
        expect(document.data, equals(kMockDocumentSnapshotData));
        // Flush the async removeListener call
        await new Future<Null>.delayed(Duration.ZERO);
        expect(log, <Matcher>[
          isMethodCall(
            'Query#addSnapshotListener',
            arguments: <String, dynamic>{
              'path': 'foo',
              'parameters': <String, dynamic>{
                'where': <List<dynamic>>[],
                'orderBy': <List<dynamic>>[],
              }
            },
          ),
          isMethodCall(
            'Query#removeListener',
            arguments: <String, dynamic>{'handle': 0},
          ),
        ]);
      });
      test('where', () async {
        final StreamSubscription<QuerySnapshot> subscription =
            collectionReference
                .where('createdAt', isLessThan: 100)
                .snapshots
                .listen((QuerySnapshot querySnapshot) {});
        subscription.cancel();
        await new Future<Null>.delayed(Duration.ZERO);
        expect(
          log,
          equals(<Matcher>[
            isMethodCall(
              'Query#addSnapshotListener',
              arguments: <String, dynamic>{
                'path': 'foo',
                'parameters': <String, dynamic>{
                  'where': <List<dynamic>>[
                    <dynamic>['createdAt', '<', 100],
                  ],
                  'orderBy': <List<dynamic>>[],
                }
              },
            ),
            isMethodCall(
              'Query#removeListener',
              arguments: <String, dynamic>{'handle': 0},
            ),
          ]),
        );
      });
      test('where field isNull', () async {
        final StreamSubscription<QuerySnapshot> subscription =
            collectionReference
                .where('profile', isNull: true)
                .snapshots
                .listen((QuerySnapshot querySnapshot) {});
        subscription.cancel();
        await new Future<Null>.delayed(Duration.ZERO);
        expect(
          log,
          equals(<Matcher>[
            isMethodCall(
              'Query#addSnapshotListener',
              arguments: <String, dynamic>{
                'path': 'foo',
                'parameters': <String, dynamic>{
                  'where': <List<dynamic>>[
                    <dynamic>['profile', '==', null],
                  ],
                  'orderBy': <List<dynamic>>[],
                }
              },
            ),
            isMethodCall(
              'Query#removeListener',
              arguments: <String, dynamic>{'handle': 0},
            ),
          ]),
        );
      });
      test('orderBy', () async {
        final StreamSubscription<QuerySnapshot> subscription =
            collectionReference
                .orderBy('createdAt')
                .snapshots
                .listen((QuerySnapshot querySnapshot) {});
        subscription.cancel();
        await new Future<Null>.delayed(Duration.ZERO);
        expect(
          log,
          equals(<Matcher>[
            isMethodCall(
              'Query#addSnapshotListener',
              arguments: <String, dynamic>{
                'path': 'foo',
                'parameters': <String, dynamic>{
                  'where': <List<dynamic>>[],
                  'orderBy': <List<dynamic>>[
                    <dynamic>['createdAt', false]
                  ],
                }
              },
            ),
            isMethodCall(
              'Query#removeListener',
              arguments: <String, dynamic>{'handle': 0},
            ),
          ]),
        );
      });
    });

    group('DocumentReference', () {
      test('listen', () async {
        final DocumentSnapshot snapshot =
            await Firestore.instance.document('path/to/foo').snapshots.first;
        expect(snapshot.documentID, equals('foo'));
        expect(snapshot.reference.path, equals('path/to/foo'));
        expect(snapshot.data, equals(kMockDocumentSnapshotData));
        // Flush the async removeListener call
        await new Future<Null>.delayed(Duration.ZERO);
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'Query#addDocumentListener',
              arguments: <String, dynamic>{
                'path': 'path/to/foo',
              },
            ),
            isMethodCall(
              'Query#removeListener',
              arguments: <String, dynamic>{'handle': 0},
            ),
          ],
        );
      });
      test('set', () async {
        await collectionReference
            .document('bar')
            .setData(<String, String>{'bazKey': 'quxValue'});
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'DocumentReference#setData',
              arguments: <String, dynamic>{
                'path': 'foo/bar',
                'data': <String, String>{'bazKey': 'quxValue'},
                'options': null,
              },
            ),
          ],
        );
      });
      test('merge set', () async {
        await collectionReference
            .document('bar')
            .setData(<String, String>{'bazKey': 'quxValue'}, SetOptions.merge);
        expect(SetOptions.merge, isNotNull);
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'DocumentReference#setData',
              arguments: <String, dynamic>{
                'path': 'foo/bar',
                'data': <String, String>{'bazKey': 'quxValue'},
                'options': <String, bool>{'merge': true},
              },
            ),
          ],
        );
      });
      test('update', () async {
        await collectionReference
            .document('bar')
            .updateData(<String, String>{'bazKey': 'quxValue'});
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'DocumentReference#updateData',
              arguments: <String, dynamic>{
                'path': 'foo/bar',
                'data': <String, String>{'bazKey': 'quxValue'},
              },
            ),
          ],
        );
      });
      test('delete', () async {
        await collectionReference.document('bar').delete();
        expect(
          log,
          equals(<Matcher>[
            isMethodCall(
              'DocumentReference#delete',
              arguments: <String, dynamic>{'path': 'foo/bar'},
            ),
          ]),
        );
      });
      test('get', () async {
        final DocumentSnapshot snapshot =
            await collectionReference.document('bar').get();
        expect(
          log,
          equals(<Matcher>[
            isMethodCall(
              'DocumentReference#get',
              arguments: <String, dynamic>{'path': 'foo/bar'},
            ),
          ]),
        );
        expect(snapshot.reference.path, equals('foo/bar'));
        expect(snapshot.data.containsKey('key1'), equals(true));
        expect(snapshot.data['key1'], equals('val1'));
        expect(snapshot.exists, isTrue);

        final DocumentSnapshot snapshot2 =
            await collectionReference.document('notExists').get();
        expect(snapshot2.data, isNull);
        expect(snapshot2.exists, isFalse);

        try {
          await collectionReference.document('baz').get();
        } on PlatformException catch (e) {
          expect(e.code, equals('UNKNOWN_PATH'));
        }
      });
      test('getCollection', () async {
        final CollectionReference colRef =
            collectionReference.document('bar').getCollection('baz');
        expect(colRef.path, 'foo/bar/baz');
      });
    });

    group('Query', () {
      test('getDocuments', () async {
        final QuerySnapshot snapshot = await collectionReference.getDocuments();
        final DocumentSnapshot document = snapshot.documents.first;
        expect(
          log,
          equals(
            <Matcher>[
              isMethodCall(
                'Query#getDocuments',
                arguments: <String, dynamic>{
                  'path': 'foo',
                  'parameters': <String, dynamic>{
                    'where': <List<dynamic>>[],
                    'orderBy': <List<dynamic>>[],
                  },
                },
              ),
            ],
          ),
        );
        expect(document.documentID, equals('0'));
        expect(document.reference.path, equals('foo/0'));
        expect(document.data, equals(kMockDocumentSnapshotData));

    group('FirestoreMessageCodec', () {
      const MessageCodec<dynamic> standard = const FirestoreMessageCodec();
      test('should encode integers correctly at boundary cases', () {
        _checkEncoding<dynamic>(
          standard,
          -0x7fffffff - 1,
          <int>[3, 0x00, 0x00, 0x00, 0x80],
        );
        _checkEncoding<dynamic>(
          standard,
          -0x7fffffff - 2,
          <int>[4, 0xff, 0xff, 0xff, 0x7f, 0xff, 0xff, 0xff, 0xff],
        );
        _checkEncoding<dynamic>(
          standard,
          0x7fffffff,
          <int>[3, 0xff, 0xff, 0xff, 0x7f],
        );
        _checkEncoding<dynamic>(
          standard,
          0x7fffffff + 1,
          <int>[4, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00],
        );
        _checkEncoding<dynamic>(
          standard,
          -0x7fffffffffffffff - 1,
          <int>[4, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80],
        );
        _checkEncoding<dynamic>(
          standard,
          -0x7fffffffffffffff - 2,
          <int>[5, 17]..addAll('-8000000000000001'.codeUnits),
        );
        _checkEncoding<dynamic>(
          standard,
          0x7fffffffffffffff,
          <int>[4, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f],
        );
        _checkEncoding<dynamic>(
          standard,
          0x7fffffffffffffff + 1,
          <int>[5, 16]..addAll('8000000000000000'.codeUnits),
        );
      });
      test('should encode sizes correctly at boundary cases', () {
        _checkEncoding<dynamic>(
          standard,
          new Uint8List(253),
          <int>[8, 253]..addAll(new List<int>.filled(253, 0)),
        );
        _checkEncoding<dynamic>(
          standard,
          new Uint8List(254),
          <int>[8, 254, 254, 0]..addAll(new List<int>.filled(254, 0)),
        );
        _checkEncoding<dynamic>(
          standard,
          new Uint8List(0xffff),
          <int>[8, 254, 0xff, 0xff]..addAll(new List<int>.filled(0xffff, 0)),
        );
        _checkEncoding<dynamic>(
          standard,
          new Uint8List(0xffff + 1),
          <int>[8, 255, 0, 0, 1, 0]
            ..addAll(new List<int>.filled(0xffff + 1, 0)),
        );
      });
      test('should encode and decode simple messages', () {
        _checkEncodeDecode<dynamic>(standard, null);
        _checkEncodeDecode<dynamic>(standard, true);
        _checkEncodeDecode<dynamic>(standard, false);
        _checkEncodeDecode<dynamic>(standard, 7);
        _checkEncodeDecode<dynamic>(standard, -7);
        _checkEncodeDecode<dynamic>(standard, 98742923489);
        _checkEncodeDecode<dynamic>(standard, -98742923489);
        _checkEncodeDecode<dynamic>(standard, 98740023429234899324932473298438);
        _checkEncodeDecode<dynamic>(
            standard, -98740023429234899324932473298438);
        _checkEncodeDecode<dynamic>(standard, 3.14);
        _checkEncodeDecode<dynamic>(standard, double.INFINITY);
        _checkEncodeDecode<dynamic>(standard, double.NAN);
        _checkEncodeDecode<dynamic>(standard, '');
        _checkEncodeDecode<dynamic>(standard, 'hello');
        _checkEncodeDecode<dynamic>(
            standard, 'special chars >\u263A\u{1F602}<');
        _checkEncodeDecode<dynamic>(standard, new DateTime.now());
        _checkEncodeDecode<dynamic>(
            standard, const GeoPoint(37.421939, -122.083509));
        _checkEncodeDecode<dynamic>(standard, firestore.document('foo/bar'));
      });
      test('should encode and decode composite message', () {
        final List<dynamic> message = <dynamic>[
          null,
          true,
          false,
          -707,
          -7000000007,
          -70000000000000000000000000000000000000000000000007,
          -3.14,
          '',
          'hello',
          new DateTime.now(),
          const GeoPoint(37.421939, -122.083509),
          firestore.document('foo/bar'),
          new Uint8List.fromList(<int>[0xBA, 0x5E, 0xBA, 0x11]),
          new Int32List.fromList(<int>[-0x7fffffff - 1, 0, 0x7fffffff]),
          null, // ensures the offset of the following list is unaligned.
          new Int64List.fromList(
              <int>[-0x7fffffffffffffff - 1, 0, 0x7fffffffffffffff]),
          null, // ensures the offset of the following list is unaligned.
          new Float64List.fromList(<double>[
            double.NEGATIVE_INFINITY,
            -double.MAX_FINITE,
            -double.MIN_POSITIVE,
            -0.0,
            0.0,
            double.MIN_POSITIVE,
            double.MAX_FINITE,
            double.INFINITY,
            double.NAN
          ]),
          <dynamic>['nested', <dynamic>[]],
          <dynamic, dynamic>{'a': 'nested', null: <dynamic, dynamic>{}},
          'world',
        ];
        _checkEncodeDecode<dynamic>(standard, message);
      });
      test('should align doubles to 8 bytes', () {
        _checkEncoding<dynamic>(
          standard,
          1.0,
          <int>[6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xf0, 0x3f],
        );
      });
    });
  });
}

void _checkEncoding<T>(
    MessageCodec<T> codec, T message, List<int> expectedBytes) {
  final ByteData encoded = codec.encodeMessage(message);
  expect(
    encoded.buffer.asUint8List(0, encoded.lengthInBytes),
    orderedEquals(expectedBytes),
  );
}

void _checkEncodeDecode<T>(MessageCodec<T> codec, T message) {
  final ByteData encoded = codec.encodeMessage(message);
  final T decoded = codec.decodeMessage(encoded);
  if (message == null) {
    expect(encoded, isNull);
    expect(decoded, isNull);
  } else {
    expect(_deepEquals(message, decoded), isTrue);
    final ByteData encodedAgain = codec.encodeMessage(decoded);
    expect(
      encodedAgain.buffer.asUint8List(),
      orderedEquals(encoded.buffer.asUint8List()),
    );
  }
}

bool _deepEquals(dynamic valueA, dynamic valueB) {
  if (valueA is TypedData)
    return valueB is TypedData && _deepEqualsTypedData(valueA, valueB);
  if (valueA is List) return valueB is List && _deepEqualsList(valueA, valueB);
  if (valueA is Map) return valueB is Map && _deepEqualsMap(valueA, valueB);
  if (valueA is double && valueA.isNaN) return valueB is double && valueB.isNaN;
  return valueA == valueB;
}

bool _deepEqualsTypedData(TypedData valueA, TypedData valueB) {
  if (valueA is ByteData) {
    return valueB is ByteData &&
        _deepEqualsList(
            valueA.buffer.asUint8List(), valueB.buffer.asUint8List());
  }
  if (valueA is Uint8List)
    return valueB is Uint8List && _deepEqualsList(valueA, valueB);
  if (valueA is Int32List)
    return valueB is Int32List && _deepEqualsList(valueA, valueB);
  if (valueA is Int64List)
    return valueB is Int64List && _deepEqualsList(valueA, valueB);
  if (valueA is Float64List)
    return valueB is Float64List && _deepEqualsList(valueA, valueB);
  throw 'Unexpected typed data: $valueA';
}

bool _deepEqualsList(List<dynamic> valueA, List<dynamic> valueB) {
  if (valueA.length != valueB.length) return false;
  for (int i = 0; i < valueA.length; i++) {
    if (!_deepEquals(valueA[i], valueB[i])) return false;
  }
  return true;
}

bool _deepEqualsMap(
    Map<dynamic, dynamic> valueA, Map<dynamic, dynamic> valueB) {
  if (valueA.length != valueB.length) return false;
  for (final dynamic key in valueA.keys) {
    if (!valueB.containsKey(key) || !_deepEquals(valueA[key], valueB[key]))
      return false;
  }
  return true;
}
