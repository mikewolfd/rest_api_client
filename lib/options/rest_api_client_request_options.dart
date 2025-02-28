import 'package:dio/dio.dart';

class RestApiClientRequestOptions {
  Map<String, dynamic>? headers;
  Options? options;
  String? contentType;
  bool silentException;

  RestApiClientRequestOptions({
    this.headers,
    this.options,
    this.contentType,
    this.silentException = false,
  });

  Options toOptions() {
    return options?.copyWith(
          headers: headers,
          contentType: contentType,
        ) ??
        Options(
          headers: headers,
          contentType: contentType,
        );
  }
}
