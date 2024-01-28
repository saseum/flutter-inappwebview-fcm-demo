import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'firebase_options.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  initializeNotification();

  if (Platform.isAndroid) {
    await AndroidInAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  runApp(const MyApp());
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("백그라운드 메시지 처리.. ${message.notification!.body!}");
}

void initializeNotification() async {
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(const AndroidNotificationChannel(
          'high_importance_channel', 'high_importance_notification',
          importance: Importance.max));

  await flutterLocalNotificationsPlugin.initialize(const InitializationSettings(
    android: AndroidInitializationSettings("@mipmap/ic_launcher"),
  ));

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var messageString = "";
  String _responseText = '';

  Future<String> _getMyDeviceToken() async {
    final token = await FirebaseMessaging.instance.getToken();

    print("=== 내 디바이스 토큰: $token");

    return token!;
  }

  Future<void> _postData() async {
    String data = await _getMyDeviceToken();
    final response = await http.post(
      Uri.parse('http://192.168.0.7:8080/endpoint'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{'data': data}),
    );

    if (response.statusCode == 200) {
      setState(() {
        print('=== response = ${response.body}');
        _responseText = 'Data sent successfully!';
      });
    } else {
      setState(() {
        _responseText = 'Failed to send data';
      });
    }
  }

  final GlobalKey webViewKey = GlobalKey();

  // 인앱웹뷰 컨트롤러
  InAppWebViewController? webViewController;
  InAppWebViewGroupOptions options = InAppWebViewGroupOptions(
    // 플랫폼 상관없이 동작하는 옵션
      crossPlatform: InAppWebViewOptions(
        useShouldOverrideUrlLoading: true, // URL 로딩 제어
        mediaPlaybackRequiresUserGesture: false, // 미디어 자동 재생
        javaScriptEnabled: true, // 자바스크립트 실행여부
        javaScriptCanOpenWindowsAutomatically: true, // 팝업 여부
      ),
      // 안드로이드 옵션
      android: AndroidInAppWebViewOptions(
        useHybridComposition: true, // 하이브리드 사용을 위한 안드로이드 웹뷰 최적화
      ),
      // iOS 옵션
      ios: IOSInAppWebViewOptions(
        allowsInlineMediaPlayback: true, // 웹뷰 내 미디어 재생 허용
      ));

  late PullToRefreshController pullToRefreshController; // 당겨서 새로고침 컨트롤러
  String url = "";
  double progress = 0;
  final urlController = TextEditingController();

  @override
  void initState() {
    _postData();
    super.initState();

    pullToRefreshController = PullToRefreshController(
      options: PullToRefreshOptions(
        color: Colors.blue, // 새로고침 아이콘 색상
      ),
      // 플랫폼별 새로고침
      onRefresh: () async {
        if (Platform.isAndroid) {
          webViewController?.reload();
        } else if (Platform.isIOS) {
          webViewController?.loadUrl(
              urlRequest: URLRequest(url: await webViewController?.getUrl()));
        }
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text("Official InAppWebView website")),
        body: SafeArea(
            child: Column(children: <Widget>[
              TextField(
                decoration: InputDecoration(prefixIcon: Icon(Icons.search)),
                controller: urlController,
                keyboardType: TextInputType.url,
                onSubmitted: (value) {
                  var url = Uri.parse(value);
                  if (url.scheme.isEmpty) {
                    url = Uri.parse("https://www.google.com/search?q=" + value);
                  }
                  webViewController?.loadUrl(urlRequest: URLRequest(url: url));
                },
              ),
              Expanded(
                child: Stack(
                  children: [
                    InAppWebView(
                      key: webViewKey,
                      // 시작페이지
                      initialUrlRequest:
                      URLRequest(url: Uri.parse("http://192.168.0.7:8080")),
                      // 초기 설정
                      initialOptions: options,
                      // 당겨서 새로고침 컨트롤러 정의
                      pullToRefreshController: pullToRefreshController,
                      // 인앱웹뷰 생성 시 컨트롤러 정의
                      onWebViewCreated: (controller) {
                        webViewController = controller;
                      },
                      // 페이지 로딩 시 수행 메서드 정의
                      onLoadStart: (controller, url) {
                        setState(() {
                          this.url = url.toString();
                          urlController.text = this.url;
                        });
                      },
                      // 안드로이드 웹뷰에서 권한 처리 메서드 정의
                      androidOnPermissionRequest:
                          (controller, origin, resources) async {
                        return PermissionRequestResponse(
                            resources: resources,
                            action: PermissionRequestResponseAction.GRANT);
                      },
                      // URL 로딩 제어
                      shouldOverrideUrlLoading:
                          (controller, navigationAction) async {
                        var uri = navigationAction.request.url!;

                        // 아래의 키워드가 포함되면 페이지 로딩
                        if (![
                          "http",
                          "https",
                          "file",
                          "chrome",
                          "data",
                          "javascript",
                          "about"
                        ].contains(uri.scheme)) {
                          if (await canLaunchUrl(Uri.parse(url))) {
                            // Launch the App
                            await launchUrl(
                              Uri.parse(url),
                            );
                            // and cancel the request
                            return NavigationActionPolicy.CANCEL;
                          }
                        }

                        return NavigationActionPolicy.ALLOW;
                      },
                      // 페이지 로딩이 정지 시 메서드 정의
                      onLoadStop: (controller, url) async {
                        // 당겨서 새로고침 중단
                        pullToRefreshController.endRefreshing();
                        setState(() {
                          this.url = url.toString();
                          urlController.text = this.url;
                        });
                      },
                      // 페이지 로딩 중 오류 발생 시 메서드 정의
                      onLoadError: (controller, url, code, message) {
                        // 당겨서 새로고침 중단
                        pullToRefreshController.endRefreshing();
                      },
                      // 로딩 상태 변경 시 메서드 정의
                      onProgressChanged: (controller, progress) {
                        // 로딩이 완료되면 당겨서 새로고침 중단
                        if (progress == 100) {
                          pullToRefreshController.endRefreshing();
                        }
                        // 현재 페이지 로딩 상태 업데이트(0~100%)
                        setState(() {
                          this.progress = progress / 100;
                          urlController.text = this.url;
                        });
                      },
                      onUpdateVisitedHistory: (controller, url, androidIsReload) {
                        setState(() {
                          this.url = url.toString();
                          urlController.text = this.url;
                        });
                      },
                      onConsoleMessage: (controller, consoleMessage) {
                        print(consoleMessage);
                      },
                    ),
                    progress < 1.0
                        ? LinearProgressIndicator(value: progress)
                        : Container(),
                  ],
                ),
              ),
              ButtonBar(
                alignment: MainAxisAlignment.center,
                children: <Widget>[
                  ElevatedButton(
                    child: Icon(Icons.arrow_back),
                    onPressed: () {
                      webViewController?.goBack();
                    },
                  ),
                  ElevatedButton(
                    child: Icon(Icons.arrow_forward),
                    onPressed: () {
                      webViewController?.goForward();
                    },
                  ),
                  ElevatedButton(
                    child: Icon(Icons.refresh),
                    onPressed: () {
                      webViewController?.reload();
                    },
                  ),
                ],
              ),
            ])));
  }
}
