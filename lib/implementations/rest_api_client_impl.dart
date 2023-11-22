import 'dart:async';
import 'dart:io';

import 'package:dio/io.dart';
import 'package:rest_api_client/options/cache_options.dart';
import 'package:rest_api_client/options/rest_api_client_request_options.dart';

import 'dio_adapter_stub.dart'
    if (dart.library.io) 'dio_adapter_mobile.dart'
    if (dart.library.js) 'dio_adapter_web.dart';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:rest_api_client/constants/rest_api_client_keys.dart';
import 'package:rest_api_client/implementations/auth_handler.dart';
import 'package:rest_api_client/implementations/cache_handler.dart';
import 'package:rest_api_client/implementations/exception_handler.dart';
import 'package:rest_api_client/implementations/rest_api_client.dart';
import 'package:rest_api_client/models/result.dart';
import 'package:rest_api_client/options/auth_options.dart';
import 'package:rest_api_client/options/exception_options.dart';
import 'package:rest_api_client/options/logging_options.dart';
import 'package:rest_api_client/options/rest_api_client_options.dart';

class RestApiClientImpl implements RestApiClient {
  late Dio _dio;

  late RestApiClientOptions _options;
  late ExceptionOptions _exceptionOptions;
  late LoggingOptions _loggingOptions;
  late AuthOptions _authOptions;
  late CacheOptions _cacheOptions;

  @override
  late AuthHandler authHandler;

  @override
  late CacheHandler cacheHandler;

  @override
  late ExceptionHandler exceptionHandler;

  RestApiClientImpl({
    required RestApiClientOptions options,
    ExceptionOptions? exceptionOptions,
    LoggingOptions? loggingOptions,
    AuthOptions? authOptions,
    CacheOptions? cacheOptions,
    List<Interceptor> interceptors = const [],
  }) {
    _options = options;
    _exceptionOptions = exceptionOptions ?? ExceptionOptions();
    _loggingOptions = loggingOptions ?? LoggingOptions();
    _authOptions = authOptions ?? AuthOptions();
    _cacheOptions = cacheOptions ?? CacheOptions();

    _dio = Dio(BaseOptions(baseUrl: _options.baseUrl));

    _dio.httpClientAdapter = getAdapter();

    exceptionHandler = ExceptionHandler(exceptionOptions: _exceptionOptions);

    authHandler = AuthHandler(
        dio: _dio,
        options: options,
        exceptionOptions: _exceptionOptions,
        authOptions: _authOptions,
        loggingOptions: _loggingOptions);

    cacheHandler = CacheHandler(
        loggingOptions: _loggingOptions, cacheOptions: _cacheOptions);

    _configureLogging();
    _addInterceptors(interceptors);
    _configureCertificateOverride();
  }

  Future<RestApiClient> init() async {
    await authHandler.init();
    await cacheHandler.init();

    return this;
  }

  @override
  Future<Result<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    FutureOr<T> Function(dynamic data)? parser,
    RestApiClientRequestOptions? options,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        options: options?.toOptions(),
      );

      if (_options.cacheEnabled) {
        await cacheHandler.set(response);
      }

      return NetworkResult(
        data: await _resolveResult(
          response.data,
          parser,
        ),
      );
    } on DioException catch (e) {
      await exceptionHandler.handle(e);

      return NetworkResult(
        exception: e,
        statusCode: e.response?.statusCode,
        statusMessage: e.response?.statusMessage,
      );
    }
  }

  @override
  Future<Result<T>> getCached<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    FutureOr<T> Function(dynamic data)? parser,
  }) async {
    final requestOptions = RequestOptions(
      path: path,
      queryParameters: queryParameters,
      headers: _dio.options.headers,
    );

    return CacheResult(
      data: await _resolveResult(
        (await cacheHandler.get(requestOptions)),
        parser,
      ),
    );
  }

  @override
  Stream<Result<T>> getStreamed<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    FutureOr<T> Function(dynamic data)? parser,
    RestApiClientRequestOptions? options,
  }) async* {
    final cachedResult = await getCached(
      path,
      queryParameters: queryParameters,
      parser: parser,
    );

    if (cachedResult.hasData) {
      yield cachedResult;
    }

    yield await get(
      path,
      queryParameters: queryParameters,
      parser: parser,
      options: options,
    );
  }

  @override
  Future<Result<T>> post<T>(
    String path, {
    data,
    Map<String, dynamic>? queryParameters,
    FutureOr<T> Function(dynamic data)? parser,
    RestApiClientRequestOptions? options,
    bool cacheEnabled = false,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options?.toOptions(),
      );

      if (cacheEnabled) {
        await cacheHandler.set(response);
      }

      return NetworkResult(
        data: await _resolveResult(
          response.data,
          parser,
        ),
      );
    } on DioException catch (e) {
      await exceptionHandler.handle(e);

      return NetworkResult(
        exception: e,
        statusCode: e.response?.statusCode,
        statusMessage: e.response?.statusMessage,
      );
    }
  }

  @override
  Future<Result<T>> postCached<T>(
    String path, {
    data,
    Map<String, dynamic>? queryParameters,
    FutureOr<T> Function(dynamic data)? parser,
  }) async {
    final requestOptions = RequestOptions(
      path: path,
      queryParameters: queryParameters,
      data: data,
      headers: _dio.options.headers,
    );

    return CacheResult(
      data: await _resolveResult(
        (await cacheHandler.get(requestOptions)),
        parser,
      ),
    );
  }

  @override
  Stream<Result<T>> postStreamed<T>(
    String path, {
    data,
    Map<String, dynamic>? queryParameters,
    FutureOr<T> Function(dynamic data)? parser,
    RestApiClientRequestOptions? options,
  }) async* {
    final cachedResult = await postCached(
      path,
      queryParameters: queryParameters,
      data: data,
      parser: parser,
    );

    if (cachedResult.hasData) {
      yield cachedResult;
    }

    yield await post(
      path,
      queryParameters: queryParameters,
      data: data,
      parser: parser,
      options: options,
    );
  }

  @override
  Future<Result<T>> put<T>(
    String path, {
    data,
    Map<String, dynamic>? queryParameters,
    FutureOr<T> Function(dynamic data)? parser,
    RestApiClientRequestOptions? options,
  }) async {
    try {
      final response = await _dio.put(
        path,
        queryParameters: queryParameters,
        data: data,
        options: options?.toOptions(),
      );

      return NetworkResult(
        data: await _resolveResult(response.data, parser),
      );
    } on DioException catch (e) {
      await exceptionHandler.handle(e);

      return NetworkResult(
        exception: e,
        statusCode: e.response?.statusCode,
        statusMessage: e.response?.statusMessage,
      );
    }
  }

  @override
  Future<Result<T>> head<T>(
    String path, {
    data,
    Map<String, dynamic>? queryParameters,
    FutureOr<T> Function(dynamic data)? parser,
    RestApiClientRequestOptions? options,
  }) async {
    try {
      final response = await _dio.head(
        path,
        queryParameters: queryParameters,
        data: data,
        options: options?.toOptions(),
      );

      return NetworkResult(
        data: await _resolveResult(response.data, parser),
      );
    } on DioException catch (e) {
      await exceptionHandler.handle(e);

      return NetworkResult(
        exception: e,
        statusCode: e.response?.statusCode,
        statusMessage: e.response?.statusMessage,
      );
    }
  }

  @override
  Future<Result<T>> delete<T>(
    String path, {
    data,
    Map<String, dynamic>? queryParameters,
    FutureOr<T> Function(dynamic data)? parser,
    RestApiClientRequestOptions? options,
  }) async {
    try {
      final response = await _dio.delete(
        path,
        queryParameters: queryParameters,
        data: data,
        options: options?.toOptions(),
      );

      return NetworkResult(
        data: await _resolveResult(response.data, parser),
      );
    } on DioException catch (e) {
      await exceptionHandler.handle(e);

      return NetworkResult(
        exception: e,
        statusCode: e.response?.statusCode,
        statusMessage: e.response?.statusMessage,
      );
    }
  }

  @override
  Future<Result<T>> patch<T>(
    String path, {
    data,
    Map<String, dynamic>? queryParameters,
    FutureOr<T> Function(dynamic data)? parser,
    RestApiClientRequestOptions? options,
  }) async {
    try {
      final response = await _dio.patch(
        path,
        queryParameters: queryParameters,
        data: data,
        options: options?.toOptions(),
      );

      return NetworkResult(
        data: await _resolveResult(response.data, parser),
      );
    } on DioException catch (e) {
      await exceptionHandler.handle(e);

      return NetworkResult(
        exception: e,
        statusCode: e.response?.statusCode,
        statusMessage: e.response?.statusMessage,
      );
    }
  }

  @override
  Future<Result<T>> download<T>(
    String urlPath,
    savePath, {
    data,
    Map<String, dynamic>? queryParameters,
    RestApiClientRequestOptions? options,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    String lengthHeader = Headers.contentLengthHeader,
    FutureOr<T> Function(dynamic data)? parser,
  }) async {
    try {
      final response = await _dio.download(
        urlPath,
        savePath,
        queryParameters: queryParameters,
        options: options?.toOptions(),
        data: data,
        onReceiveProgress: onReceiveProgress,
        cancelToken: cancelToken,
        deleteOnError: deleteOnError,
        lengthHeader: lengthHeader,
      );

      return NetworkResult(
        data: await _resolveResult(response.data, parser),
      );
    } on DioException catch (e) {
      await exceptionHandler.handle(e);

      return NetworkResult(
        exception: e,
        statusCode: e.response?.statusCode,
        statusMessage: e.response?.statusMessage,
      );
    }
  }

  void setContentType(String contentType) =>
      _dio.options.contentType = contentType;

  @override
  Future clearStorage() async {
    await authHandler.clear();
    await cacheHandler.clear();
  }

  void _configureLogging() {
    if (_loggingOptions.logNetworkTraffic) {
      _dio.interceptors.add(
        PrettyDioLogger(
          responseBody: _loggingOptions.responseBody,
          requestBody: _loggingOptions.requestBody,
          requestHeader: _loggingOptions.requestHeader,
          request: _loggingOptions.request,
          responseHeader: _loggingOptions.responseHeader,
          compact: _loggingOptions.compact,
          error: _loggingOptions.error,
        ),
      );
    }
  }

  void _addInterceptors(List<Interceptor> interceptors) {
    _dio.interceptors.addAll(interceptors);

    _addRefreshTokenInterceptor();
  }

  void _addRefreshTokenInterceptor() {
    _dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onRequest: (RequestOptions options, handler) {
          options.extra.addAll({
            'showInternalServerErrors':
                _exceptionOptions.showInternalServerErrors
          });
          options.extra.addAll(
              {'showNetworkErrors': _exceptionOptions.showNetworkErrors});
          options.extra.addAll(
              {'showValidationErrors': _exceptionOptions.showValidationErrors});

          return handler.next(options);
        },
        onResponse: (Response response, handler) {
          _exceptionOptions.reset();

          return handler.next(response);
        },
        onError: (DioException error, handler) async {
          if (authHandler.usesAuth &&
              error.response?.statusCode == HttpStatus.unauthorized) {
            try {
              return handler
                  .resolve(await authHandler.refreshTokenCallback(error));
            } catch (e) {
              print(e);
            }
          }

          await exceptionHandler.handle(error, error.requestOptions.extra);

          return handler.next(error);
        },
      ),
    );
  }

  void _configureCertificateOverride() {
    if (_options.overrideBadCertificate && !kIsWeb) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();

        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;

        return client;
      };
    }
  }

  void setAcceptLanguageHeader(String languageCode) => addOrUpdateHeader(
      key: RestApiClientKeys.acceptLanguage, value: languageCode);

  Future<bool> authorize(
      {required String jwt, required String refreshToken}) async {
    return await authHandler.authorize(jwt: jwt, refreshToken: refreshToken);
  }

  Future<bool> unAuthorize() async {
    return await authHandler.unAuthorize();
  }

  Future<bool> isAuthorized() async {
    return await authHandler.isAuthorized();
  }

  void addOrUpdateHeader({required String key, required String value}) =>
      _dio.options.headers.containsKey(key)
          ? _dio.options.headers.update(key, (v) => value)
          : _dio.options.headers.addAll({key: value});

  FutureOr<T?> _resolveResult<T>(dynamic data,
      [FutureOr<T> Function(dynamic data)? parser]) async {
    if (data != null) {
      if (parser != null) {
        return await parser(data);
      } else {
        return data as T;
      }
    } else {
      return null;
    }
  }
}
