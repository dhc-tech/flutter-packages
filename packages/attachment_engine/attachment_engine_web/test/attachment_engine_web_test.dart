// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:attachment_engine_web/attachment_engine_web.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registerWith sets the platform instance', () {
    AttachmentEngineWeb.registerWith();
    expect(AttachmentEnginePlatform.instance, isA<AttachmentEngineWebImpl>());
  });

  test('shareFile is not yet implemented', () {
    final impl = AttachmentEngineWebImpl();
    expect(() => impl.shareFile('x'), throwsUnimplementedError);
  });
}
