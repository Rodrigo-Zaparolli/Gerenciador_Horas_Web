import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

String recoveryError(Object error, {String operation = 'concluir a operação'}) {
  final code = error is FirebaseException ? error.code : '';
  final message = error.toString().toLowerCase();
  if (error is FirebaseAuthException ||
      message.contains('entre novamente') ||
      message.contains('conta mudou') ||
      message.contains('não autenticado') ||
      ['unauthenticated', 'permission-denied'].contains(code)) {
    return 'Sua sessão ou permissão precisa ser verificada. Entre novamente na conta e tente $operation.';
  }
  if (error is TimeoutException ||
      ['unavailable', 'deadline-exceeded'].contains(code)) {
    return 'Não foi possível conectar. Verifique a internet e tente $operation novamente.';
  }
  return 'Não foi possível $operation. Tente novamente. Se persistir, confira a conexão e o estado da integração.';
}
