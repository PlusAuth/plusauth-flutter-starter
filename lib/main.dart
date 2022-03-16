import 'package:flutter/material.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlusAuth Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _isLoading = false;
  bool _isLoggedIn = false;
  String? _userName;
  String? _userInfo;
  String? _refreshToken;
  String? _accessToken;
  String? _idToken;

  // AppAuth OIDC client object
  final FlutterAppAuth _appAuth = FlutterAppAuth();

  // Initialize storage to store refresh token after login
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  final String _clientId = '<YOUR_CLIENT_ID>';
  final String _issuer = 'https://<YOUR_TENANT>.plusauth.com';
  final String _userInfoUrl = 'https://<YOUR_TENANT>.plusauth.com/oidc/userinfo';
  final String _redirectUrl = 'com.plusauth.flutterexample:/oauthredirect/login';
  final String _postLogoutRedirectUrl = 'com.plusauth.flutterexample:/';
  final List<String> _scopes = <String>['openid', 'profile', 'email', 'offline_access'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PlusAuth Flutter Demo'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Visibility(
                visible: _isLoading,
                child: const LinearProgressIndicator(), // Loading Bar
              ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Welcome to PlusAuth Flutter Demo!',
                  style: TextStyle( fontSize: 21.0 )
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Username: ${_userName ?? '-'}',
                    style: const TextStyle( fontSize: 18.0 )
                ),
              ),
              Visibility(
                child: ElevatedButton(
                  child: const Text('Login'),
                  onPressed: _signIn,
                  style: ButtonStyle(
                      padding: MaterialStateProperty.all(const EdgeInsets.fromLTRB(36, 12, 36, 12)),
                      backgroundColor: MaterialStateProperty.all(Colors.blue),
                      foregroundColor: MaterialStateProperty.all(Colors.white),
                      textStyle: MaterialStateProperty.all(const TextStyle(fontSize: 18))
                  ),
                ),
                visible: !_isLoggedIn,
              ),
              Visibility(
                child: ElevatedButton(
                  child: const Text('Logout'),
                  onPressed: _singOut,
                  style: ButtonStyle(
                      padding: MaterialStateProperty.all(const EdgeInsets.fromLTRB(36, 12, 36, 12)),
                      backgroundColor: MaterialStateProperty.all(Colors.red),
                      foregroundColor: MaterialStateProperty.all(Colors.white),
                      textStyle: MaterialStateProperty.all(const TextStyle(fontSize: 18))
                  ),
                ),
                visible: _isLoggedIn,
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_userInfo ?? '',
                    style: const TextStyle( fontSize: 16.0 )
                ),
              ),
            ],
          ),
        )
      ),
    );
  }

  @override
  void initState() {
    initAction();
    super.initState();
  }

  void initAction() async {
    // Get refresh token if exists
    _refreshToken = await _secureStorage.read(key: 'refresh_token');
    if(_refreshToken != null) _refreshAuthToken();
  }

  // Set loading state
  void _setLoading(isLoading) {
    setState(() {
      _isLoading = isLoading;
    });
  }

  Future<void> _signIn() async {
    try {
      _setLoading(true);
      final AuthorizationTokenResponse? result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest( _clientId, _redirectUrl, issuer: _issuer, scopes: _scopes),
      );
      if (result != null) {
        // process and extract tokens from response
        _processAuthTokenResponse(result);
      }
    } catch (_) {
    } finally {
      _setLoading(false);
    }
  }

  // Process login response
  void _processAuthTokenResponse(AuthorizationTokenResponse response) {
    // Save refresh token to storage to exchange with new one
    _secureStorage.write(key: 'refresh_token', value: response.refreshToken);
    setState(() {
      _isLoggedIn = true;
      _accessToken = response.accessToken!;
      _idToken =  response.idToken!;
      _refreshToken = response.refreshToken!;
    });
    _fetchUserInfo();
  }

  Future<void> _refreshAuthToken() async {
    try {
      _setLoading(true);
      // Get new token using refresh token
      final TokenResponse? result = await _appAuth.token(TokenRequest(
          _clientId, _redirectUrl, refreshToken: _refreshToken, issuer: _issuer, scopes: _scopes));
      _processTokenResponse(result);
    } catch (_) {
      _clearSessionInfo();
    } finally {
      _setLoading(false);
    }
  }

  // Process refresh token exchange response
  void _processTokenResponse(TokenResponse? response) {
    _secureStorage.write(key: 'refresh_token', value: response!.refreshToken);
    setState(() {
      _isLoggedIn = true;
      _accessToken = response.accessToken!;
      _idToken = response.idToken!;
      _refreshToken = response.refreshToken!;
    });
    _fetchUserInfo();
  }

  Future<void> _singOut() async {
    try {
      _setLoading(true);
      // User Logout
      await _appAuth.endSession(EndSessionRequest(idTokenHint: _idToken, postLogoutRedirectUrl: _postLogoutRedirectUrl, issuer: _issuer));
      _clearSessionInfo();
    } catch (_) {}
    finally {
      _setLoading(false);
    }
  }

  // Clear and delete all session info
  void _clearSessionInfo() {
    _secureStorage.delete(key: 'refresh_token');
    setState(() {
      _isLoggedIn = false;
      _userName = null;
      _userInfo = null;
      _accessToken = null;
      _idToken = null;
      _refreshToken = null;
    });
  }

  // Get signed in user info
  Future<void> _fetchUserInfo() async {
    _setLoading(true);
    final http.Response httpResponse = await http.get(Uri.parse(_userInfoUrl  ),
        headers: <String, String>{'Authorization': 'Bearer $_accessToken'});
    final body = json.decode(httpResponse.body);

    setState(() {
      _userName = body['username'];
      _userInfo = httpResponse.statusCode == 200 ? httpResponse.body : '';
    });
    _setLoading(false);
  }
}
