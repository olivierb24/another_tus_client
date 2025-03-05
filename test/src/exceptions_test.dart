import 'package:test/test.dart';
import 'package:another_tus_client/another_tus_client.dart';

main() {
  test("exceptions_test.ProtocolException", () {
    final err = ProtocolException("Expected HEADER 'Tus-Resumable'");
    expect(
        "$err",
        "ProtocolException: "
            "Expected HEADER 'Tus-Resumable'");
  });

  test("exceptions_test.ProtocolException.response.shouldRetry", () {
    final err = ProtocolException("Expected HEADER 'Tus-Resumable'");
    expect(
        "$err",
        "ProtocolException: "
            "Expected HEADER 'Tus-Resumable'");
  });

  test("exceptions_test.ProtocolException.response.shouldNotRetry", () {
    final err = ProtocolException("Expected HEADER 'Tus-Resumable'");
    expect(
        "$err",
        "ProtocolException: "
            "Expected HEADER 'Tus-Resumable'");
  });
}
