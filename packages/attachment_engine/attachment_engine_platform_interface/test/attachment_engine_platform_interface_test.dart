import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlatform extends AttachmentEnginePlatform {}

void main() {
  test('default instance is set and can be overridden by a valid subclass', () {
    expect(AttachmentEnginePlatform.instance, isNotNull);
    final fake = _FakePlatform();
    AttachmentEnginePlatform.instance = fake;
    expect(AttachmentEnginePlatform.instance, same(fake));
  });

  test('unimplemented methods throw UnimplementedError by default', () {
    final platform = _FakePlatform();
    expect(() => platform.pdfOpen('x'), throwsUnimplementedError);
    expect(() => platform.shareText('x'), throwsUnimplementedError);
    expect(
      () => platform.getApplicationCacheDirectory(),
      throwsUnimplementedError,
    );
    expect(() => platform.openOfficePreview('x'), throwsUnimplementedError);
  });
}
