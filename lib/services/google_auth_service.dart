import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:googleapis/tasks/v1.dart' as tasks;
import 'package:http/http.dart' as http;

/// Nomes de lista do Google Tasks tratados como "lista de compras".
/// A tela de Compras usa essas listas; o Calendário as ignora.
const nomesListasCompras = [
  'compras',
  'compra',
  'lista de compras',
  'shopping',
  'mercado',
  'supermercado',
  'feira',
];

bool ehListaDeCompras(String titulo) {
  final t = titulo.toLowerCase().trim();
  return nomesListasCompras.any(t.contains);
}

/// Cliente HTTP que injeta o token do Google em cada requisição.
class _ClienteAutenticado extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();
  _ClienteAutenticado(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) {
    r.headers.addAll(_headers);
    return _inner.send(r);
  }

  @override
  void close() => _inner.close();
}

/// Login Google compartilhado por Calendário e Compras.
///
/// Regra importante para um painel de parede: durante o rodízio o app só
/// tenta o login SILENCIOSO. A janela de escolher conta (que exige alguém
/// tocando na tela) só abre quando o usuário toca em "Conectar" nas
/// Configurações — antes ela podia pular no meio do rodízio.
class GoogleAuthService extends ChangeNotifier {
  GoogleAuthService._();
  static final GoogleAuthService instance = GoogleAuthService._();

  final _signIn = GoogleSignIn(scopes: [
    cal.CalendarApi.calendarReadonlyScope,
    tasks.TasksApi.tasksScope,
  ]);

  GoogleSignInAccount? _conta;
  GoogleSignInAccount? get conta => _conta;
  bool get conectado => _conta != null;

  /// Cliente pronto para as APIs do Google, ou null se não houver conta
  /// conectada (nesse caso a tela mostra "Conecte nas Configurações").
  Future<http.Client?> cliente() async {
    try {
      _conta ??= await _signIn.signInSilently();
      final c = _conta;
      if (c == null) return null;
      return _ClienteAutenticado(await c.authHeaders);
    } catch (e) {
      debugPrint('GoogleAuthService.cliente: $e');
      return null;
    }
  }

  /// Abre a janela de login. Chamar só a partir de um toque do usuário.
  Future<bool> conectar() async {
    try {
      _conta = await _signIn.signIn();
      notifyListeners();
      return _conta != null;
    } catch (e) {
      debugPrint('GoogleAuthService.conectar: $e');
      return false;
    }
  }

  Future<void> desconectar() async {
    try {
      await _signIn.disconnect();
    } catch (_) {
      await _signIn.signOut();
    }
    _conta = null;
    notifyListeners();
  }

  /// Verifica (sem abrir janela) se já existe conta conectada.
  Future<void> verificar() async {
    try {
      _conta = await _signIn.signInSilently();
    } catch (_) {}
    notifyListeners();
  }
}
